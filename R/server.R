#' Run a survey in a Shiny app
#'
#' `survey_ui()` and `survey_server()` are a Shiny module pair. Give both the
#' same `id`. The app owns the chat and the connection: it makes them, passes
#' them in, and closes the connection when it stops.
#'
#' @param id The module id. It must be the same in the UI and the server.
#' @param survey A survey spec from [survey_spec()].
#' @param chat An ellmer chat, such as [ellmer::chat_claude()]. Each LLM call
#'   uses a copy with no history, so one chat can serve all users.
#' @param con A DBI connection or a `pool::dbPool()`. The server makes the
#'   tables with [init_database()] if they are not there.
#' @return `survey_server()` returns no value; it is called for its side
#'   effects.
#' @export
#' @examplesIf interactive() && rlang::is_installed("RSQLite")
#' library(shiny)
#'
#' survey <- survey_spec() |>
#'   add_question(
#'     "color",
#'     text = "What's your favorite color?",
#'     answer = ellmer::type_string("The color")
#'   )
#'
#' chat <- ellmer::chat_claude(echo = "none")
#' con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
#' onStop(\() DBI::dbDisconnect(con))
#'
#' ui <- survey_ui("survey", title = "Colors")
#' server <- function(input, output, session) {
#'   survey_server("survey", survey, chat, con)
#' }
#' shinyApp(ui, server)
survey_server <- function(id, survey, chat, con) {
  validate_spec(survey)
  check_backends(chat, con)
  config <- survey$config

  shiny::moduleServer(id, function(input, output, session) {
    engine <- NULL
    started <- FALSE
    total <- length(survey$questions)
    progress <- shiny::reactiveVal(list(current = 1, complete = FALSE))
    finished <- shiny::reactiveVal(FALSE)

    output$progress <- shiny::renderUI({
      state <- progress()
      survey_progress(state$current, total, complete = state$complete)
    })

    output$footer <- shiny::renderUI({
      if (finished()) {
        survey_complete(survey$messages$closed, session$ns("chat"))
      }
    })

    # Streams a message into the chat and returns the stream's promise. The
    # generator reads its arguments only when the stream starts, so `message`
    # is forced here to run its side effects now.
    send <- function(message) {
      force(message)
      shinychat::chat_append(
        "chat",
        bot_response(
          message,
          response_delay = config$response_delay,
          character_delay = config$character_delay,
          delay_variance = config$delay_variance
        ),
        session = session
      )
    }

    track <- function() {
      progress(list(current = engine$progress()$current, complete = FALSE))
    }

    # Starts once, when the session is live, and sends the first question as a
    # separate message after the welcome
    shiny::observe({
      if (started) {
        return()
      }
      started <<- TRUE
      engine <<- SurveySession$new(survey, chat, con)
      shiny::onStop(\() if (!is.null(engine)) engine$close())

      welcome <- engine$start()
      send(welcome)
      track()
      first <- engine$first_question()
      later::later(\() send(first), delay = 1.5)
    })

    shiny::observeEvent(input$chat_user_input, {
      if (is.null(engine)) {
        return()
      }
      result <- engine$process_input(input$chat_user_input)
      if (is.null(result$message)) {
        return()
      }

      if (result$complete) {
        progress(list(current = total, complete = TRUE))
        # Retire the input only after the closing message has streamed
        promises::then(send(result$message), \(...) finished(TRUE))
        engine$close()
        engine <<- NULL
      } else {
        send(result$message)
        track()
      }
    })
  })
}
