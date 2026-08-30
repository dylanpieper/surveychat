#' Shiny server logic for the chat survey

box::use(
  shiny[observe, observeEvent, onStop],
  R/config[default_config],
  R/stream[bot_response],
  R/survey[Survey],
)

#' Survey in Shiny server
#' @param input Shiny input object
#' @param output Shiny output object
#' @param session Shiny session object
#' @param chat Chat object for AI interactions
#' @param questions List of survey questions
#' @param messages Message templates
#' @param content Content generation templates
#' @param config Optional configuration (uses defaults if not provided)
#' @export
chat_survey <- function(input, output, session, chat, questions, messages,
                        content, config = default_config()) {
  survey <- NULL
  initialized <- FALSE

  # Stream a message into the chat UI
  send <- function(message) {
    shinychat::chat_append("chat", bot_response(
      message,
      response_delay = config$response_delay,
      character_delay = config$character_delay,
      delay_variance = config$delay_variance
    ), session = session)
  }

  # Initialize survey and send first question
  observe({
    if (!initialized) {
      initialized <<- TRUE
      survey <<- Survey(chat, questions, messages, content, config)

      # Setup cleanup on session end
      onStop(\() {
        if (!is.null(survey)) {
          survey$cleanup()
        }
      })

      # Send welcome message first
      send(survey$init())

      # Send first question as separate message after delay
      first_question <- survey$get_first_question()
      later::later(function() send(first_question), delay = 1.5)
    }
  })

  # Handle user responses
  observeEvent(input$chat_user_input, {
    if (is.null(survey)) {
      return()
    }

    result <- survey$process_input(input$chat_user_input)

    if (!is.null(result$message)) {
      send(result$message)

      # Survey finished
      if (result$complete) {
        survey$cleanup()
        survey <<- NULL
      }
    }
  })
}
