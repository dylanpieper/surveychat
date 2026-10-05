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
#' start (see the `views` of [set_config()]) starts when the page loads.
#' @section Form:
#' The form shows one question at a time, as the chat does. Each kept form
#' answer is written to the chat transcript as a user message after its
#' question, so the chat shows the survey when the user switches to it. A
#' form answer that is asked again shows its hint under the field only.
#' When the survey is complete, the form shows the `completion` message of
#' [set_messages()].
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
  views <- config$views %||% "chat"
  methods <- view_methods(views)
  start_view <- views[[1]]
  questions <- stats::setNames(survey$questions, question_ids(survey))

  shiny::moduleServer(id, function(input, output, session) {
    # The view and the state of the form show from the first flush, also
    # when the survey locks before it starts
    view <- shiny::reactiveVal(start_view)
    status <- shiny::reactiveVal("waiting")
    prompt <- shiny::reactiveVal(NULL)
    form_error <- shiny::reactiveVal(NULL)
    completion <- shiny::reactiveVal(NULL)

    output$view <- shiny::renderText(view())
    shiny::outputOptions(output, "view", suspendWhenHidden = FALSE)

    # Rendered once; the browser keeps the active button
    output$method <- shiny::renderUI({
      if (length(views) > 1) {
        view_picker(session$ns("view_pick"), shiny::isolate(view()), views)
      }
    })
    shiny::observeEvent(input$view_pick, {
      if (rlang::is_string(input$view_pick, views)) {
        view(input$view_pick)
      }
    })

    output$form <- shiny::renderUI({
      switch(
        status(),
        waiting = survey_waiter(session$ns("form_waiter")),
        locked = survey_status(survey$messages$locked, "locked"),
        # The form shows the completion message, rendered with the answers
        # escaped, and under it the closed message with its check mark, as
        # the chat does
        complete = htmltools::tagList(
          if (!is.null(completion())) {
            htmltools::div(class = "sb-form-completion", completion())
          },
          survey_status(survey$messages$closed)
        ),
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
    progress <- shiny::reactiveVal(list(
      current = 1,
      total = length(survey$questions),
      complete = FALSE
    ))
    finished <- shiny::reactiveVal(FALSE)

    output$progress <- shiny::renderUI({
      state <- progress()
      survey_progress(state$current, state$total, complete = state$complete)
    })

    output$footer <- shiny::renderUI({
      if (finished()) {
        survey_complete(survey$messages$closed, session$ns("chat"))
      }
    })

    # Adds a message to the chat after the messages before it have streamed,
    # so two messages never stream at the same time. Returns the promise of
    # this message. `delay` waits that many seconds before it starts. A
    # failed message is logged, and the next message still streams.
    queue <- promises::promise_resolve(NULL)
    send <- function(message, role = "assistant", delay = 0) {
      force(message)
      queue <<- promises::then(queue, \(...) {
        promises::then(pause(delay), \(...) {
          if (role == "ui") {
            return(shinychat::chat_append("chat", message, session = session))
          }
          if (role == "user") {
            return(shinychat::chat_append(
              "chat",
              message,
              role = "user",
              session = session
            ))
          }
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
        })
      })
      queue <<- promises::catch(queue, \(err) {
        cli::cli_warn("The survey could not show a chat message.", parent = err)
        NULL
      })
      queue
    }

    track <- function() {
      progress(c(engine$progress(), complete = FALSE))
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
      ask(first, delay = 0.5)
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
        progress(c(engine$progress(), complete = TRUE))
        completion(render_message(
          result$closing$template,
          result$closing$data
        ))
        status("complete")
        remove_widget()
        # Retire the input only after the closing message has streamed
        promises::then(send(result$message), \(...) finished(TRUE))
        engine$close()
        engine <<- NULL
      } else {
        ask(result$message)
        track()
      }
      invisible()
    }

    # Sends a question to the chat. A question with choices, a yes or no, a
    # date, or a multi-select also gets its input below it, one time. The
    # input of the question before leaves the chat, such as when the user
    # answered it by typing or in the form.
    widget_for <- NULL
    ask <- function(message, delay = 0) {
      send(message, delay = delay)
      current <- engine$current_prompt()
      if (is.null(current) || identical(current$id, widget_for)) {
        return(invisible())
      }
      remove_widget()
      question <- questions[[current$id]]
      if ("chat" %in% methods && has_chat_input(question)) {
        widget <- chat_input(session$ns, current, question)
        if (!is.null(widget)) {
          widget_for <<- current$id
          send(widget, "ui")
        }
      }
      invisible()
    }

    remove_widget <- function() {
      if (!is.null(widget_for)) {
        shiny::removeUI(
          paste0("#", session$ns(paste0("chat_widget_", widget_for))),
          session = session
        )
        widget_for <<- NULL
      }
      invisible()
    }

    # A value from an input in the chat is a chat answer with no LLM call:
    # a click on a choice, or Send under a date or checkboxes. The input
    # leaves the chat once its answer is kept.
    take_chat_value <- function(id, value) {
      if (is.null(engine) || !identical(engine$current_prompt()$id, id)) {
        return(invisible())
      }
      result <- tryCatch(
        engine$submit_form(value, method = "chat"),
        error = function(err) {
          cli::cli_warn(
            "The survey could not handle a chat input.",
            parent = err
          )
          list(message = NULL, complete = FALSE, error = survey$messages$retry)
        }
      )
      if (!is.null(result$error)) {
        send(result$error)
        return(invisible())
      }
      if (is.null(result$message)) {
        return(invisible())
      }
      remove_widget()
      send(form_echo(questions[[id]], value, survey$messages$skipped), "user")
      step(result)
    }
    for (id in names(Filter(has_chat_input, questions))) {
      local({
        id <- id
        shiny::observeEvent(input[[paste0("chat_pick_", id)]], {
          take_chat_value(id, input[[paste0("chat_pick_", id)]])
        })
        shiny::observeEvent(input[[paste0("chat_send_", id)]], {
          take_chat_value(id, input[[paste0("chat_input_", id)]])
        })
      })
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

    # A kept form answer goes into the chat as a user message, as the user
    # saw it, so the chat shows each kept answer after its question
    # Takes a form answer: the inputs of the step after Next, or the value of
    # a one-click choice. A choice for a question that is no longer current,
    # such as a click while Next waits for the LLM, changes nothing.
    take_form_value <- function(value, id = NULL) {
      current <- prompt()
      if (is.null(engine) || is.null(current)) {
        return(invisible())
      }
      if (!is.null(id) && !identical(current$id, id)) {
        return(invisible())
      }
      question <- questions[[current$id]]
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
        return(invisible())
      }
      if (is.null(result$message)) {
        return(invisible())
      }
      send(form_echo(question, value, survey$messages$skipped), role = "user")
      step(result)
    }
    shiny::observeEvent(input$form_next, {
      current <- prompt()
      if (!is.null(current)) {
        take_form_value(form_read(input, current))
      }
    })
    for (id in names(questions)) {
      local({
        id <- id
        pick_id <- paste0("form_pick_", id)
        shiny::observeEvent(input[[pick_id]], {
          take_form_value(input[[pick_id]], id)
        })
      })
    }
  })
}

# A promise that resolves after `seconds`
pause <- function(seconds) {
  if (seconds <= 0) {
    return(promises::promise_resolve(NULL))
  }
  promises::promise(\(resolve, reject) {
    later::later(\() resolve(NULL), delay = seconds)
  })
}
