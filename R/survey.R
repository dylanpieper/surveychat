# Survey state machine for one user session ----
#
# The server makes one SurveySession for each Shiny session. It holds the
# answers, writes each reply to the database, and returns the next message.
# A reply comes from the chat (`process_input()`) or the form
# (`submit_form()`). Both return `list(message, complete)`; `message` is NULL
# while an earlier reply is still in progress or after the survey is
# complete. A form answer that is not kept also gives `error`.
#
# Both views show one question at a time: the first question with no
# answer. Each question is rendered once into a prompt, `list(id, intro,
# text, generated, fixed)`. The chat shows it as a message and the form as
# an input, so a switch between the views generates nothing again.

SurveySession <- R6::R6Class(
  "SurveySession",
  public = list(
    initialize = function(spec, chat, con) {
      private$questions <- spec$questions
      private$ids <- vapply(spec$questions, \(question) question$id, "")
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
        methods = view_methods(private$config$views %||% "chat")
      )
      private$session_start <- now()
      private$question_start <- now()
      private$messages$welcome
    },

    # The message of the first question. It can have an intro, but it is
    # never adaptive.
    first_question = function() {
      private$next_question()$message
    },

    # The prompt of the current question, or NULL after the survey
    current_prompt = function() {
      if (private$complete) {
        return(NULL)
      }
      private$current
    },

    # The accepted answers so far, named by question id
    answers_so_far = function() {
      private$answers
    },

    # The total counts only the questions that can still apply, so the
    # progress does not jump when a `when` rule skips a question
    progress = function() {
      counted <- vapply(
        seq_along(private$questions),
        private$counts,
        logical(1)
      )
      total <- sum(counted)
      current <- sum(counted & private$ids %in% private$done_ids) + 1
      list(current = min(current, total), total = total)
    },

    process_input = function(user_input) {
      if (private$busy) {
        return(list(message = NULL, complete = FALSE))
      }
      if (private$complete) {
        return(list(message = NULL, complete = TRUE))
      }
      private$busy <- TRUE
      on.exit(private$busy <- FALSE)

      # Only a failed extraction or response insert asks for the reply again;
      # nothing has changed yet, so the retry is safe and is not counted
      i <- private$q_num
      question <- private$questions[[i]]
      prompt <- self$current_prompt()
      later <- private$later_questions()
      reply <- tryCatch(
        {
          extracted <- extract_response(
            private$chat,
            prompt$text,
            user_input,
            extraction_schema(question, later, private$answers),
            early = length(later) > 0,
            answers = private$answers,
            asked = private$asked
          )
          answer <- normalize_answer(question, extracted[[question$id]])
          fits <- answer_fits(question, answer)
          if (!fits) {
            answer <- NA
          }
          valid <- isTRUE(extracted$valid) && fits
          private$record(i, user_input, answer, valid = valid, method = "chat")
          list(
            extracted = extracted,
            answer = answer,
            valid = valid,
            fits = fits
          )
        },
        error = function(err) {
          cli::cli_warn(
            "Could not process the reply to question {.val {question$id}}.",
            parent = err
          )
          NULL
        }
      )
      if (is.null(reply)) {
        return(list(message = private$messages$retry, complete = FALSE))
      }
      private$update_duration()

      if (
        !reply$valid && private$retries_of(question$id) < private$config$tries
      ) {
        private$count_retry(question$id)
        return(list(
          message = if (reply$fits) {
            private$retry_message(reply$extracted)
          } else {
            private$messages$date
          },
          complete = FALSE
        ))
      }

      private$keep(question, reply$answer)
      # A reply kept only because the retries ran out gives no early answers
      if (reply$valid) {
        private$take_early(later, reply$extracted, user_input)
      }
      private$next_question()
    },

    # Takes the answer to the current question from the form. A value with
    # the wrong type records nothing. Typed text, or any answer to a question
    # with its own `valid` rule, goes through the same LLM extraction as the
    # chat: an answer that is not valid is asked again, up to `tries` times,
    # and gives the LLM hint or the retry message as `error`. A fixed choice
    # needs no LLM call and is valid. If the LLM call fails, the form answer
    # is kept with `valid = NA`. An input in the chat, such as a date
    # picker, gives its value here too, with `method = "chat"`.
    submit_form = function(value, method = "form") {
      if (private$busy) {
        return(list(message = NULL, complete = FALSE))
      }
      if (private$complete) {
        return(list(message = NULL, complete = TRUE))
      }
      private$busy <- TRUE
      on.exit(private$busy <- FALSE)

      error <- private$submit_one(private$q_num, value, method)
      if (!is.null(error)) {
        return(list(message = NULL, complete = FALSE, error = error))
      }
      private$next_question()
    },

    # The caller opened the connection and closes it; this drops the reference
    close = function() {
      private$con <- NULL
      invisible(self)
    }
  ),

  private = list(
    questions = NULL,
    ids = NULL,
    messages = NULL,
    config = NULL,
    chat = NULL,
    con = NULL,
    session_id = NULL,
    session_start = NULL,
    question_start = NULL,
    q_num = 0,
    current = NULL,
    answers = list(),
    # The question text that the user saw for each kept answer, by id
    asked = list(),
    done_ids = character(),
    not_applied = character(),
    retries = list(),
    complete = FALSE,
    busy = FALSE,

    record = function(i, answer_raw, answer, valid, method) {
      id <- private$ids[[i]]
      answer <- stored_answer(private$questions[[i]], answer)
      save_response(
        private$con,
        session_id = private$session_id,
        question_id = id,
        question_order = i,
        question_text = private$current$text,
        answer_raw = answer_raw,
        answer_extracted = answer,
        valid = valid,
        retry_attempt = private$retries_of(id),
        duration_seconds = elapsed(private$question_start),
        method = method
      )
    },

    # Checks and records the form answer to question `i`. Returns NULL if
    # the answer is kept, or else the message for the user.
    submit_one = function(i, value, method) {
      question <- private$questions[[i]]
      id <- question$id
      prompt <- private$current
      checked <- form_value(question, value)
      if (!checked$ok) {
        return(checked$error)
      }
      answer <- checked$value
      valid <- TRUE
      extracted <- NULL
      if (form_needs_validation(question, prompt, checked$raw)) {
        extracted <- tryCatch(
          extract_response(
            private$chat,
            prompt$text,
            checked$raw,
            dated_schema(question),
            answers = private$answers,
            asked = private$asked
          ),
          error = function(err) {
            cli::cli_warn(
              "Could not check the form answer to question {.val {id}}; the survey keeps it.",
              parent = err
            )
            NULL
          }
        )
        if (is.null(extracted)) {
          valid <- NA
        } else {
          # The form value of a date is already YYYY-MM-DD, so it stays if
          # the extracted date does not fit
          answer <- normalize_answer(question, extracted[[id]])
          if (!answer_fits(question, answer)) {
            answer <- checked$value
          }
          valid <- isTRUE(extracted$valid)
        }
      }
      saved <- tryCatch(
        {
          private$record(i, checked$raw, answer, valid = valid, method = method)
          TRUE
        },
        error = function(err) {
          cli::cli_warn(
            "Could not record the form answer to question {.val {id}}.",
            parent = err
          )
          FALSE
        }
      )
      if (!saved) {
        return(private$messages$retry)
      }
      private$update_duration()
      if (isFALSE(valid) && private$retries_of(id) < private$config$tries) {
        private$count_retry(id)
        return(private$retry_message(extracted))
      }
      private$keep(question, answer)
      NULL
    },

    # Keeps the answer and marks the question done. A skipped optional
    # answer is not kept, so templates use a fallback.
    keep = function(question, answer) {
      if (any(!is.na(answer))) {
        private$answers[[question$id]] <- answer
        private$asked[[question$id]] <- private$asked_text(question)
      }
      private$done_ids <- c(private$done_ids, question$id)
      invisible(answer)
    },

    # The text of a question as the user saw it: the current prompt, or for
    # an answer given early, the fixed text. NULL for an adaptive question
    # that was never shown.
    asked_text = function(question) {
      current <- private$current
      if (!is.null(current) && identical(current$id, question$id)) {
        return(current$text)
      }
      if (is_adaptive(question)) {
        return(NULL)
      }
      interpolate(question$text, private$answers, capitalize = TRUE)
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

    retries_of = function(id) {
      private$retries[[id]] %||% 0
    },

    # The chat and the form share one retry count for each question
    count_retry = function(id) {
      private$retries[[id]] <- private$retries_of(id) + 1
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

    # Whether question `i` counts in the progress. A done question counts if
    # it applied. An open question counts if its rule is TRUE, or if the rule
    # needs an answer that is not known yet.
    counts = function(i) {
      question <- private$questions[[i]]
      if (question$id %in% private$not_applied) {
        return(FALSE)
      }
      if (question$id %in% private$done_ids || is.null(question$when)) {
        return(TRUE)
      }
      if (!all(question$when_ids %in% private$done_ids)) {
        return(TRUE)
      }
      suppressWarnings(when_applies(question, private$answers))
    },

    # The later fixed questions that a reply can answer early. Adaptive
    # questions are not known yet, so they are always asked. A question
    # whose `when` rule is not TRUE yet is left out.
    later_questions = function() {
      n <- length(private$questions)
      if (!isTRUE(private$config$skip_answered) || private$q_num >= n) {
        return(list())
      }
      later <- private$questions[seq(private$q_num + 1, n)]
      Filter(
        \(other) {
          !is_adaptive(other) &&
            !other$id %in% private$done_ids &&
            suppressWarnings(when_applies(other, private$answers))
        },
        later
      )
    },

    # Records each clear early answer as its own response, with no question
    # text. A failed write leaves the question to be asked as usual.
    take_early = function(later, extracted, user_input) {
      for (other in later) {
        value <- normalize_answer(other, extracted[[other$id]])
        if (!any(!is.na(value)) || !answer_fits(other, value)) {
          next
        }
        saved <- tryCatch(
          {
            save_response(
              private$con,
              session_id = private$session_id,
              question_id = other$id,
              question_order = match(other$id, private$ids),
              question_text = NULL,
              answer_raw = user_input,
              answer_extracted = stored_answer(other, value),
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
          private$keep(other, value)
        }
      }
      invisible(NULL)
    },

    # Moves to the first question with no answer that applies and renders.
    # A question whose `when` rule is not TRUE, or an adaptive question whose
    # generation fails, is done with no row. Past the last question, the
    # survey ends.
    next_question = function() {
      repeat {
        open <- which(!private$ids %in% private$done_ids)
        if (length(open) == 0) {
          return(private$finish())
        }
        i <- open[[1]]
        question <- private$questions[[i]]
        if (!when_applies(question, private$answers)) {
          private$not_applied <- c(private$not_applied, question$id)
          private$done_ids <- c(private$done_ids, question$id)
          next
        }
        prompt <- private$render(i)
        if (is.null(prompt)) {
          private$done_ids <- c(private$done_ids, question$id)
          next
        }
        private$q_num <- i
        private$question_start <- now()
        private$current <- prompt
        return(list(message = private$message(prompt), complete = FALSE))
      }
    },

    message = function(prompt) {
      chat_message(prompt, private$messages$suggested)
    },

    # Makes the prompt of question `i`. Returns NULL if its text cannot be
    # made. `text` is the question alone, which the database records.
    render = function(i) {
      question <- private$questions[[i]]
      text <- if (is_adaptive(question)) {
        private$ask_adaptive(question)
      } else {
        interpolate(question$text, private$answers, capitalize = TRUE)
      }
      if (is.null(text)) {
        return(NULL)
      }
      list(
        id = question$id,
        intro = private$intro(question),
        text = text,
        generated = private$generated(question),
        fixed = question$choices$fixed
      )
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
      # The choices of an enum must be its values, or no pick could be kept
      # A choice matches its value without regard to case
      values <- enum_values(question$answer)
      if (!is.null(values)) {
        generated <- values[match(tolower(generated), tolower(values))]
        generated <- unique(generated[!is.na(generated)])
      }
      # The cap comes after the filters, so no kept choice is lost to it
      generated <- utils::head(generated, max_generated_choices)
      if (length(generated) > 0) generated
    },

    # The generated intro of a question, or NULL if it has none or fails
    intro = function(question) {
      if (is.null(question$intro)) {
        return(NULL)
      }
      content <- private$generate(question$intro, question$id)
      # The question follows the intro, so the intro asks nothing, even when
      # the model writes a question despite the prompt
      if (!is.null(content)) {
        content <- drop_questions(content)
      }
      if (is.null(content) || !nzchar(content)) {
        return(NULL)
      }
      interpolate(
        question$intro$format,
        c(list(content = content), private$answers),
        capitalize = TRUE
      )
    },

    # The text of an adaptive question, or NULL when the model skips it or
    # the call fails. Only a failure gives a warning. With
    # `skip_answered = FALSE`, the model cannot skip it.
    ask_adaptive = function(question) {
      tryCatch(
        generate_question(
          private$chat,
          question$text,
          private$answers,
          allow_skip = isTRUE(private$config$skip_answered),
          asked = private$asked
        ),
        error = function(err) {
          cli::cli_warn(
            "Content generation failed for question {.val {question$id}}.",
            parent = err
          )
          NULL
        }
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
      private$complete <- TRUE
      private$soft(
        "the completion",
        complete_session(
          private$con,
          private$session_id,
          elapsed(private$session_start)
        )
      )
      closing <- private$closing()
      message <- interpolate(closing$template, closing$data, capitalize = TRUE)
      list(
        # A removed {content} can leave a gap; other text keeps its spacing
        message = if (isTRUE(closing$failed)) {
          tidy_text(message)
        } else {
          trimws(message)
        },
        complete = TRUE,
        closing = closing
      )
    },

    # The completion message as `list(template, data)`. A generated
    # completion adds its content to the answers. If the generation fails,
    # `{content|fallback}` shows its fallback and a bare `{content}` leaves
    # the format.
    closing = function() {
      completion <- private$messages$completion
      if (!inherits(completion, "surveychat_prompt")) {
        return(list(template = completion, data = private$answers))
      }
      content <- tryCatch(
        generate_content(
          private$chat,
          completion,
          private$answers,
          context = TRUE,
          asked = private$asked
        ),
        error = function(err) {
          cli::cli_warn(
            "The survey could not generate the completion message.",
            parent = err
          )
          NA_character_
        }
      )
      template <- completion$format
      if (is.na(content)) {
        template <- gsub("\\{\\s*content\\s*\\}", "", template)
      }
      list(
        template = template,
        data = c(list(content = content), private$answers),
        failed = is.na(content)
      )
    }
  )
)

# The text with runs of spaces and of blank lines made single, such as
# after an empty placeholder, and no space at the ends
tidy_text <- function(text) {
  text <- gsub("[ \t]{2,}", " ", text)
  text <- gsub("\n[ \t]*(\n[ \t]*)+\n", "\n\n", text)
  trimws(text)
}

# The clock of the engine; tests replace it
now <- function() {
  Sys.time()
}

# Whole seconds since `since`, or NULL if the clock never started
elapsed <- function(since) {
  if (is.null(since)) {
    return(NULL)
  }
  as.integer(difftime(now(), since, units = "secs"))
}
