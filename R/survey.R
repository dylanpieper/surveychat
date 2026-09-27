# Survey state machine for one user session ----
#
# The server makes one SurveySession for each Shiny session. It holds the
# answers, writes each reply to the database, and returns the next message.
# `process_input()` returns `list(message, complete)`; `message` is NULL while
# an earlier reply is still in progress or after the survey is complete.

SurveySession <- R6::R6Class(
  "SurveySession",
  public = list(
    initialize = function(spec, chat, con) {
      private$questions <- spec$questions
      private$messages <- spec$messages
      private$config <- spec$config
      private$chat <- chat
      private$con <- con
      init_database(con, quiet = TRUE)
    },

    # Opens the session row and returns the welcome message
    start = function() {
      private$session_id <- start_session(
        private$con,
        version = private$config$version
      )
      private$session_start <- Sys.time()
      private$question_start <- Sys.time()
      private$messages$welcome
    },

    # The first question can have an intro, but it is never adaptive
    first_question = function() {
      private$render(1)
    },

    progress = function() {
      total <- length(private$questions)
      list(current = min(private$q_num, total), total = total)
    },

    process_input = function(user_input) {
      if (private$busy) {
        return(list(message = NULL, complete = FALSE))
      }
      if (private$q_num > length(private$questions)) {
        return(list(message = NULL, complete = TRUE))
      }
      private$busy <- TRUE
      on.exit(private$busy <- FALSE)

      # Only a failed extraction or response insert asks for the reply again;
      # nothing has changed yet, so the retry is safe and is not counted
      question <- private$questions[[private$q_num]]
      extracted <- tryCatch(
        {
          extracted <- extract_response(
            private$chat,
            private$shown_text,
            user_input,
            question$schema
          )
          private$record(question, user_input, extracted)
          extracted
        },
        error = function(err) {
          cli::cli_warn(
            "Could not process the reply to question {.val {question$id}}.",
            parent = err
          )
          NULL
        }
      )
      if (is.null(extracted)) {
        return(list(message = private$messages$retry, complete = FALSE))
      }
      private$soft(
        "the session duration",
        update_session_duration(
          private$con,
          private$session_id,
          elapsed(private$session_start)
        )
      )
      valid <- isTRUE(extracted$valid)

      if (!valid && private$retry_count < private$config$tries) {
        private$retry_count <- private$retry_count + 1
        private$soft(
          "the retry count",
          increment_retry(private$con, private$session_id)
        )
        return(list(message = private$messages$retry, complete = FALSE))
      }

      private$answers[[question$id]] <- extracted[[question$id]]
      private$retry_count <- 0
      private$advance()
    },

    # The caller opened the connection and closes it; this drops the reference
    close = function() {
      private$con <- NULL
      invisible(self)
    }
  ),

  private = list(
    questions = NULL,
    messages = NULL,
    config = NULL,
    chat = NULL,
    con = NULL,
    session_id = NULL,
    session_start = NULL,
    question_start = NULL,
    q_num = 1,
    answers = list(),
    shown_text = NULL,
    retry_count = 0,
    busy = FALSE,

    record = function(question, user_input, extracted) {
      save_response(
        private$con,
        session_id = private$session_id,
        question_id = question$id,
        question_order = private$q_num,
        question_text = private$shown_text,
        input_raw = user_input,
        input_extracted = extracted[[question$id]],
        valid = isTRUE(extracted$valid),
        retry_attempt = private$retry_count,
        question_duration_seconds = elapsed(private$question_start)
      )
    },

    # Runs a bookkeeping write. A failure is logged and the survey continues,
    # so the engine never stops between two states.
    soft = function(what, write) {
      tryCatch(
        write,
        error = function(err) {
          cli::cli_warn(
            "Could not update {what} of session {private$session_id}; the survey continues.",
            parent = err
          )
        }
      )
      invisible(NULL)
    },

    # Moves to the next question that renders. An adaptive question whose
    # generation fails is skipped; past the last question, the survey ends.
    advance = function() {
      repeat {
        private$q_num <- private$q_num + 1
        private$question_start <- Sys.time()
        if (private$q_num > length(private$questions)) {
          return(private$finish())
        }
        message <- private$render(private$q_num)
        if (!is.null(message)) {
          return(list(message = message, complete = FALSE))
        }
      }
    },

    # Returns the message for question `i`, or NULL if its text cannot be made.
    # `shown_text` keeps the question alone, which the database records.
    render = function(i) {
      question <- private$questions[[i]]
      text <- if (is_adaptive(question)) {
        private$generate(question$text, question$id)
      } else {
        interpolate(question$text, private$answers, capitalize = TRUE)
      }
      if (is.null(text)) {
        return(NULL)
      }
      private$shown_text <- text

      if (is.null(question$intro)) {
        return(text)
      }
      content <- private$generate(question$intro, question$id)
      if (is.null(content)) {
        return(text)
      }
      intro <- interpolate(
        question$intro$format,
        c(list(content = content), private$answers),
        capitalize = TRUE
      )
      paste0(intro, "\n\n", text)
    },

    generate = function(prompt, id) {
      tryCatch(
        generate_content(private$chat, prompt, private$answers),
        error = function(err) {
          cli::cli_warn(
            "Content generation failed for question {.val {id}}.",
            parent = err
          )
          NULL
        }
      )
    },

    finish = function() {
      private$soft(
        "the completion",
        complete_session(
          private$con,
          private$session_id,
          elapsed(private$session_start)
        )
      )
      list(
        message = interpolate(
          private$messages$completion,
          private$answers,
          capitalize = TRUE
        ),
        complete = TRUE
      )
    }
  )
)

# Whole seconds since `since`, or NULL if the clock never started
elapsed <- function(since) {
  if (is.null(since)) {
    return(NULL)
  }
  as.integer(difftime(Sys.time(), since, units = "secs"))
}
