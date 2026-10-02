# Survey state machine for one user session ----
#
# The server makes one SurveySession for each Shiny session. It holds the
# answers, writes each reply to the database, and returns the next message.
# A reply comes from the chat (`process_input()`) or the form
# (`submit_form()`). Both return `list(message, complete)`; `message` is NULL
# while an earlier reply is still in progress or after the survey is
# complete. A form value with the wrong type also gives `error`.
#
# Each question is rendered once into a prompt, `list(id, intro, text,
# generated, fixed)`. The chat shows it as a message and the form as an
# input, so a switch between the views generates nothing again.

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
        version = private$config$version,
        methods = private$config$methods %||% "chat"
      )
      private$session_start <- Sys.time()
      private$question_start <- Sys.time()
      private$messages$welcome
    },

    # The first question can have an intro, but it is never adaptive
    first_question = function() {
      private$message(private$render(1))
    },

    # The prompt of the current question, or NULL after the survey
    current_prompt = function() {
      if (private$q_num > length(private$questions)) {
        return(NULL)
      }
      private$current
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
            private$current$text,
            user_input,
            extraction_schema(question, later, private$answers),
            early = length(later) > 0
          )
          private$record(
            question,
            user_input,
            extracted[[question$id]],
            valid = isTRUE(extracted$valid),
            method = "chat"
          )
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
      private$update_duration()
      valid <- isTRUE(extracted$valid)

      if (!valid && private$retry_count < private$config$tries) {
        private$count_retry()
        return(list(
          message = private$retry_message(extracted),
          complete = FALSE
        ))
      }

      private$keep(question, extracted[[question$id]])
      # A reply kept only because the retries ran out gives no early answers
      if (valid) {
        private$take_early(later, extracted, user_input)
      }
      private$retry_count <- 0
      private$advance()
    },

    # Takes the answer to the current question from the form. A value with
    # the wrong type records nothing and gives `error` for the user. Typed
    # text, or any answer to a question with its own `valid` rule, goes
    # through the same LLM extraction as the chat: an answer that is not
    # valid is asked again, up to `tries` times, and gives the LLM hint or the
    # retry message as `error`. A fixed choice needs no LLM call and is valid. If the LLM
    # call fails, the form answer is kept with `valid = NA`.
    submit_form = function(value) {
      if (private$busy) {
        return(list(message = NULL, complete = FALSE))
      }
      if (private$q_num > length(private$questions)) {
        return(list(message = NULL, complete = TRUE))
      }
      private$busy <- TRUE
      on.exit(private$busy <- FALSE)

      question <- private$questions[[private$q_num]]
      checked <- form_value(question, value)
      if (!checked$ok) {
        return(list(message = NULL, complete = FALSE, error = checked$error))
      }
      answer <- checked$value
      valid <- TRUE
      extracted <- NULL
      if (form_needs_check(question, private$current, checked$raw)) {
        extracted <- tryCatch(
          extract_response(
            private$chat,
            private$current$text,
            checked$raw,
            question$schema
          ),
          error = function(err) {
            cli::cli_warn(
              "Could not check the form answer to question {.val {question$id}}; the survey keeps it.",
              parent = err
            )
            NULL
          }
        )
        if (is.null(extracted)) {
          valid <- NA
        } else {
          answer <- extracted[[question$id]]
          valid <- isTRUE(extracted$valid)
        }
      }
      saved <- tryCatch(
        {
          private$record(
            question,
            checked$raw,
            answer,
            valid = valid,
            method = "form"
          )
          TRUE
        },
        error = function(err) {
          cli::cli_warn(
            "Could not record the form answer to question {.val {question$id}}.",
            parent = err
          )
          FALSE
        }
      )
      if (!saved) {
        return(list(
          message = NULL,
          complete = FALSE,
          error = private$messages$retry
        ))
      }
      private$update_duration()
      if (isFALSE(valid) && private$retry_count < private$config$tries) {
        private$count_retry()
        return(list(
          message = NULL,
          complete = FALSE,
          error = private$retry_message(extracted)
        ))
      }
      private$keep(question, answer)
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
    current = NULL,
    retry_count = 0,
    busy = FALSE,

    record = function(question, answer_raw, answer, valid, method) {
      save_response(
        private$con,
        session_id = private$session_id,
        question_id = question$id,
        question_order = private$q_num,
        question_text = private$current$text,
        answer_raw = answer_raw,
        answer_extracted = answer,
        valid = valid,
        retry_attempt = private$retry_count,
        duration_seconds = elapsed(private$question_start),
        method = method
      )
    },

    # A skipped optional answer is not kept, so templates use a fallback
    keep = function(question, answer) {
      if (any(!is.na(answer))) {
        private$answers[[question$id]] <- answer
      }
      invisible(answer)
    },

    # The hint that the LLM wrote for an answer that is not valid, or the
    # `retry` message if there is no hint
    retry_message = function(extracted) {
      hint <- extracted$retry_hint
      if (rlang::is_string(hint) && !is.na(hint) && nzchar(trimws(hint))) {
        return(trimws(hint))
      }
      private$messages$retry
    },

    # The chat and the form share one retry count for each question
    count_retry = function() {
      private$retry_count <- private$retry_count + 1
      private$soft(
        "the retry count",
        increment_retry(private$con, private$session_id)
      )
    },

    update_duration = function() {
      private$soft(
        "the session duration",
        update_session_duration(
          private$con,
          private$session_id,
          elapsed(private$session_start)
        )
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
              valid = TRUE,
              method = "chat"
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
        prompt <- private$render(private$q_num)
        if (!is.null(prompt)) {
          return(list(message = private$message(prompt), complete = FALSE))
        }
      }
    },

    message = function(prompt) {
      chat_message(prompt, private$messages$suggested)
    },

    # Makes the prompt of question `i` and keeps it as the current prompt.
    # Returns NULL if its text cannot be made. `text` is the question alone,
    # which the database records.
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
      private$current <- list(
        id = question$id,
        intro = private$intro(question),
        text = text,
        generated = private$generated(question),
        fixed = question$choices$fixed
      )
      private$current
    },

    # The choices that the LLM writes for a question, without those that
    # repeat a fixed choice. NULL if the question has no choice prompt or the
    # generation fails.
    generated = function(question) {
      choices <- question$choices
      if (is.null(choices$prompt)) {
        return(NULL)
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
      if (length(generated) > 0) generated
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
