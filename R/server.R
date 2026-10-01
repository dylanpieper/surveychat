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
#' @param drawer `NULL`, or a function that fills the chat drawer. It takes
#'   `answers`, a named list of the answers so far, and `complete`, `TRUE`
#'   after the last answer, and returns UI. The drawer stays closed; its
#'   toggle shows after the first answer. Use it with a
#'   [shinychat::chat_drawer()] in [survey_chat_ui()].
#' @return `survey_server()` returns no value; it is called for its side
#'   effects.
#' @section Start:
#' The survey starts when the chat first shows on the screen. Then the server
#' sends the model a short test prompt. If the model answers with text, the
#' server writes the session row and sends the welcome. If the request fails,
#' for example with an HTTP error, the survey locks and shows the `locked`
#' message of [set_messages()]. A chat in a closed sidebar starts when the user
#' opens the sidebar. To skip the test prompt, use
#' `set_config(check_model = FALSE)`. A survey that shows the form at the
#' start (see the `methods` of [set_config()]) starts when the page loads.
#' @section Form:
#' In the form view, each answer is written to the chat transcript as a user
#' message after the question, so the chat shows the full survey when the
#' user switches to it.
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
survey_server <- function(id, survey, chat, con, drawer = NULL) {
  validate_spec(survey)
  check_backends(chat, con)
  check_drawer_fn(drawer)
  config <- survey$config
  methods <- config$methods %||% "chat"
  # With both methods, the survey starts side by side
  start_view <- if (length(methods) == 2) "both" else methods
  questions <- stats::setNames(survey$questions, question_ids(survey))

  shiny::moduleServer(id, function(input, output, session) {
    # The view and the state of the form show from the first flush, also
    # when the survey locks before it starts
    view <- shiny::reactiveVal(start_view)
    status <- shiny::reactiveVal("waiting")
    prompt <- shiny::reactiveVal(NULL)
    form_error <- shiny::reactiveVal(NULL)

    output$view <- shiny::renderText(view())
    shiny::outputOptions(output, "view", suspendWhenHidden = FALSE)

    # Rendered once; the browser keeps the active button
    output$method <- shiny::renderUI({
      if (length(methods) == 2) {
        view_picker(session$ns("view_pick"), shiny::isolate(view()))
      }
    })
    shiny::observeEvent(input$view_pick, {
      if (rlang::is_string(input$view_pick, c("form", "chat", "both"))) {
        view(input$view_pick)
      }
    })

    output$form <- shiny::renderUI({
      switch(
        status(),
        waiting = survey_waiter(session$ns("form_waiter")),
        locked = survey_status(survey$messages$locked, "locked"),
        complete = survey_status(survey$messages$closed),
        form_step(session$ns, prompt(), questions[[prompt()$id]])
      )
    })
    output$form_error <- shiny::renderUI({
      if (!is.null(form_error())) {
        htmltools::div(
          class = "text-danger small mb-2",
          role = "alert",
          form_error()
        )
      }
    })

    # The waiter covers the chat until the model check ends
    hide_waiter <- function() {
      shiny::removeUI(paste0("#", session$ns("waiter")), session = session)
    }

    # A locked survey hides the input, writes no session row, and gives the
    # cause in the console
    lock <- function(reason, cause) {
      cli::cli_warn(reason, parent = cause)
      hide_waiter()
      status("locked")
      output$footer <- shiny::renderUI({
        survey_complete(
          survey$messages$locked,
          session$ns("chat"),
          status = "locked"
        )
      })
      invisible(reason)
    }

    setup_error <- chat_setup_error(chat)
    if (!is.null(setup_error)) {
      lock(
        c(
          "The survey is locked because the chat is not set up.",
          "i" = "Check the credentials of the provider, such as its API key in {.file ~/.Renviron}, then restart R."
        ),
        setup_error
      )
      return(invisible())
    }

    check_model <- !isFALSE(config$check_model)
    if (!check_model) {
      hide_waiter()
    }

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
      prompt(engine$current_prompt())
      form_error(NULL)
    }

    drawer_ready <- shiny::reactiveVal(FALSE)
    output$drawer_ready <- shiny::renderText(
      if (drawer_ready()) "ready" else ""
    )
    shiny::outputOptions(output, "drawer_ready", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$drawer_toggle, {
      shinychat::chat_drawer_toggle("chat")
    })

    # Fills the drawer when there is a new answer or at the end. The drawer
    # stays closed; its toggle shows once it has content. A failure is logged
    # and the survey continues.
    drawer_count <- 0
    fill_drawer <- function(complete = FALSE) {
      answers <- engine$answers_so_far()
      if (is.null(drawer) || length(answers) == 0) {
        return(invisible())
      }
      if (length(answers) == drawer_count && !complete) {
        return(invisible())
      }
      drawer_count <<- length(answers)
      content <- tryCatch(
        drawer(answers, complete),
        error = function(err) {
          cli::cli_warn("The survey could not fill the drawer.", parent = err)
          NULL
        }
      )
      if (is.null(content)) {
        return(invisible())
      }
      shinychat::chat_drawer_update("chat", content = content)
      drawer_ready(TRUE)
      invisible()
    }

    # Starts once and sends the first question as a separate message after
    # the welcome. With `check_model`, a model that does not answer locks the
    # survey before it starts.
    start_survey <- function() {
      if (started) {
        return(invisible())
      }
      started <<- TRUE
      if (check_model) {
        probe_error <- chat_probe_cached(chat)
        if (!is.null(probe_error)) {
          lock(
            c(
              "The survey is locked because the model did not answer.",
              "i" = "Check the status of the provider and the model name."
            ),
            probe_error
          )
          return(invisible())
        }
        hide_waiter()
      }
      engine <<- SurveySession$new(survey, chat, con)
      shiny::onStop(\() if (!is.null(engine)) engine$close())

      welcome <- engine$start()
      send(welcome)
      first <- engine$first_question()
      track()
      status("active")
      later::later(\() send(first), delay = 1.5)
      invisible()
    }

    # The chat view starts when the empty chat first shows on the screen; a
    # view with the form starts when the page loads
    shiny::observeEvent(input$chat_greeting_requested, start_survey())
    if (start_view != "chat") {
      session$onFlushed(\() shiny::isolate(start_survey()), once = TRUE)
    }

    # Shows the result of a chat or form answer in both views
    step <- function(result) {
      if (is.null(result$message)) {
        return(invisible())
      }
      fill_drawer(complete = result$complete)
      if (result$complete) {
        progress(list(current = total, complete = TRUE))
        status("complete")
        # Retire the input only after the closing message has streamed
        promises::then(send(result$message), \(...) finished(TRUE))
        engine$close()
        engine <<- NULL
      } else {
        send(result$message)
        track()
      }
      invisible()
    }

    shiny::observeEvent(input$chat_user_input, {
      if (is.null(engine)) {
        return()
      }
      # Last guard: any other error asks for the reply again, so the Shiny
      # session stays alive
      result <- tryCatch(
        engine$process_input(input$chat_user_input),
        error = function(err) {
          cli::cli_warn("The survey could not handle a reply.", parent = err)
          list(message = survey$messages$retry, complete = FALSE)
        }
      )
      step(result)
    })

    # A form answer goes into the chat as a user message, so the transcript
    # is complete when the user switches to the chat
    shiny::observeEvent(input$form_next, {
      current <- prompt()
      if (is.null(engine) || is.null(current)) {
        return()
      }
      value <- form_read(input, current, questions[[current$id]])
      result <- tryCatch(
        engine$submit_form(value),
        error = function(err) {
          cli::cli_warn(
            "The survey could not handle a form answer.",
            parent = err
          )
          list(message = NULL, complete = FALSE, error = survey$messages$retry)
        }
      )
      if (!is.null(result$error)) {
        form_error(result$error)
        return()
      }
      if (is.null(result$message)) {
        return()
      }
      reply <- form_text(value)
      shinychat::chat_append(
        "chat",
        if (nzchar(reply)) reply else "(skipped)",
        role = "user",
        session = session
      )
      step(result)
    })
  })
}
