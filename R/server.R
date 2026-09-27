# Shiny server logic for the chat survey

#' Survey in Shiny server
#' @param input Shiny input object
#' @param output Shiny output object
#' @param session Shiny session object
#' @param chat Chat object for AI interactions
#' @param con Database connection, opened and closed by the caller
#' @param questions List of survey questions
#' @param messages Message templates
#' @param content Content generation templates
#' @param config Optional configuration (uses defaults if not provided)
#' @export
chat_survey <- function(
  input,
  output,
  session,
  chat,
  con,
  questions,
  messages,
  content,
  config = default_config()
) {
  survey <- NULL
  initialized <- FALSE
  progress <- shiny::reactiveVal(list(
    current = 1,
    total = length(questions),
    complete = FALSE
  ))
  finished <- shiny::reactiveVal(FALSE)

  output$survey_progress <- shiny::renderUI({
    state <- progress()
    survey_progress(state$current, state$total, complete = state$complete)
  })

  output$survey_footer <- shiny::renderUI({
    if (finished()) survey_complete(messages$closed)
  })

  # Stream a message into the chat UI, returning the stream's promise
  send <- function(message) {
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

  # Advance the progress cue to whatever question the survey is now on
  track <- function() {
    state <- survey$get_progress()
    progress(list(
      current = state$current,
      total = state$total,
      complete = FALSE
    ))
  }

  # Initialize survey and send first question
  shiny::observe({
    if (!initialized) {
      initialized <<- TRUE
      survey <<- Survey(chat, con, questions, messages, content, config)

      # Setup cleanup on session end
      shiny::onStop(\() {
        if (!is.null(survey)) {
          survey$cleanup()
        }
      })

      # Send welcome message first
      send(survey$init())
      track()

      # Send first question as separate message after delay
      first_question <- survey$get_first_question()
      later::later(function() send(first_question), delay = 1.5)
    }
  })

  # Handle user responses
  shiny::observeEvent(input$chat_user_input, {
    if (is.null(survey)) {
      return()
    }

    result <- survey$process_input(input$chat_user_input)

    if (!is.null(result$message)) {
      # Survey finished
      if (result$complete) {
        state <- survey$get_progress()
        progress(list(
          current = state$total,
          total = state$total,
          complete = TRUE
        ))

        # Retire the input only after the closing message has streamed
        promises::then(send(result$message), \(...) finished(TRUE))

        survey$cleanup()
        survey <<- NULL
      } else {
        send(result$message)
        track()
      }
    }
  })
}
