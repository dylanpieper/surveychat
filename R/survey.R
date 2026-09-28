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

    # The accepted answers so far, named by question id
    answers_so_far = function() {
      private$answers
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
      later <- private$later_questions()
      extracted <- tryCatch(
        {
          extracted <- extract_response(
            private$chat,
            private$shown_text,
            user_input,
            extraction_schema(question, later, private$answers),
            early = length(later) > 0
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

      # A skipped optional answer is not kept, so templates use a fallback
      answer <- extracted[[question$id]]
      if (any(!is.na(answer))) {
        private$answers[[question$id]] <- answer
      }
      private$take_early(later, extracted, user_input)
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
    answered_early = character(),
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
        answer_raw = user_input,
        answer_extracted = extracted[[question$id]],
        valid = isTRUE(extracted$valid),
        retry_attempt = private$retry_count,
        duration_seconds = elapsed(private$question_start)
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

    # The later fixed questions that a reply can answer early. Adaptive
    # questions are not known yet, so they are always asked.
    later_questions = function() {
      n <- length(private$questions)
      if (!isTRUE(private$config$skip_answered) || private$q_num >= n) {
        return(list())
      }
      later <- private$questions[seq(private$q_num + 1, n)]
      Filter(
        \(other) !is_adaptive(other) && !other$id %in% private$answered_early,
        later
      )
    },

    # Records each clear early answer as its own response, with no question
    # text. A failed write leaves the question to be asked as usual.
    take_early = function(later, extracted, user_input) {
      ids <- vapply(private$questions, \(other) other$id, character(1))
      for (other in later) {
        value <- extracted[[other$id]]
        if (!any(!is.na(value))) {
          next
        }
        saved <- tryCatch(
          {
            save_response(
              private$con,
              session_id = private$session_id,
              question_id = other$id,
              question_order = match(other$id, ids),
              question_text = NULL,
              answer_raw = user_input,
              answer_extracted = value,
              valid = TRUE
            )
            TRUE
          },
          error = function(err) {
            cli::cli_warn(
              "Could not record the early answer to question {.val {other$id}}; the survey will ask it.",
              parent = err
            )
            FALSE
          }
        )
        if (saved) {
          private$answers[[other$id]] <- value
          private$answered_early <- c(private$answered_early, other$id)
        }
      }
      invisible(NULL)
    },

    # Moves to the next question that renders. A question answered early, or
    # an adaptive question whose generation fails, is skipped; past the last
    # question, the survey ends.
    advance = function() {
      repeat {
        private$q_num <- private$q_num + 1
        private$question_start <- Sys.time()
        if (private$q_num > length(private$questions)) {
          return(private$finish())
        }
        if (private$questions[[private$q_num]]$id %in% private$answered_early) {
          next
        }
        message <- private$render(private$q_num)
        if (!is.null(message)) {
          return(list(message = message, complete = FALSE))
        }
      }
    },

    # Returns the message for question `i`, or NULL if its text cannot be made.
    # The message is the typed text, then the choice cards if there are any.
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
      c(
        paste(c(private$intro(question), text), collapse = "\n\n"),
        private$cards(question)
      )
    },

    # The choice cards of a question, or NULL if it has none. Generated
    # choices come after a note that tells the user they are from the LLM;
    # the fixed choices follow in their own list, so they always show. If the
    # generation fails, only the fixed choices show.
    cards = function(question) {
      choices <- question$choices
      fixed <- suggestion_cards(choices$fixed)
      if (is.null(choices$prompt)) {
        return(fixed)
      }
      generated <- tryCatch(
        generate_choices(private$chat, choices$prompt, private$answers),
        error = function(err) {
          cli::cli_warn(
            "Choice generation failed for question {.val {question$id}}.",
            parent = err
          )
          NULL
        }
      )
      generated <- generated[!tolower(generated) %in% tolower(choices$fixed)]
      ideas <- if (length(generated) > 0) {
        paste0(private$messages$suggested, "\n\n", suggestion_cards(generated))
      }
      parts <- c(ideas, fixed)
      if (length(parts) == 0) NULL else paste(parts, collapse = "\n\n")
    },

    # The generated intro of a question, or NULL if it has none or fails
    intro = function(question) {
      if (is.null(question$intro)) {
        return(NULL)
      }
      content <- private$generate(question$intro, question$id)
      if (is.null(content)) {
        return(NULL)
      }
      interpolate(
        question$intro$format,
        c(list(content = content), private$answers),
        capitalize = TRUE
      )
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
