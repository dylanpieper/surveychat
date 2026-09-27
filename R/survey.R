# Survey state machine

#' Create a Survey class instance
#' @param chat Chat object for AI interactions
#' @param con Database connection, owned by the caller
#' @param questions List of survey questions
#' @param messages Message templates
#' @param content Content generation templates
#' @param config Application configuration (optional, uses defaults)
#' @return Survey class instance
#' @export
Survey <- function(
  chat,
  con,
  questions,
  messages,
  content,
  config = default_config()
) {
  init_database(con, quiet = TRUE)

  self <- list(
    # State
    chat = chat,
    con = con,
    questions = questions,
    messages = messages,
    content = content,
    config = config,

    # Survey state
    q_num = 1,
    responses = list(),
    retry_count = 0,
    session_id = NULL,
    processing = FALSE,
    session_start_time = NULL,
    question_start_time = NULL
  )

  # Initialize database session and return welcome message
  self$init <- function() {
    self$session_id <<- start_session(self$con, version = self$config$version)
    self$session_start_time <<- Sys.time()
    self$question_start_time <<- Sys.time()
    self$messages$welcome
  }

  # Seconds since a start time, or NULL if the clock was never started
  elapsed <- function(since) {
    if (is.null(since)) {
      return(NULL)
    }
    as.integer(difftime(Sys.time(), since, units = "secs"))
  }

  # Get first question text
  self$get_first_question <- function() {
    self$questions[[1]]$text
  }

  # Current question number and total, read live from the survey state
  self$get_progress <- function() {
    list(
      current = min(self$q_num, length(self$questions)),
      total = length(self$questions)
    )
  }

  # Release the survey's hold on the connection. The caller opened it and is
  # responsible for closing it, so this only drops the reference.
  self$cleanup <- function() {
    self$con <<- NULL
  }

  # Process user input and return message to send
  self$process_input <- function(user_input) {
    if (self$processing) {
      return(list(message = NULL, complete = FALSE))
    }

    self$processing <<- TRUE

    # Get current question
    current_q <- self$questions[[self$q_num]]

    # Extract and save response
    extracted_data <- extract_response(self$chat, user_input, current_q$schema)
    field_name <- current_q$id
    answered_clearly <- extracted_data$answered_clearly

    # Determine question text for database
    question_text <- if (
      !is.null(current_q$content) &&
        current_q$content == "follow_up"
    ) {
      self$responses$adaptive_question_text
    } else {
      personalize_text(current_q$text, self$responses)
    }

    # Calculate question duration
    question_duration <- elapsed(self$question_start_time)

    # Save to database
    save_response(
      self$con,
      session_id = self$session_id,
      question_id = current_q$id,
      question_order = self$q_num,
      question_text = question_text,
      input_raw = user_input,
      input_extracted = extracted_data[[field_name]],
      answered_clearly = answered_clearly,
      retry_attempt = self$retry_count,
      question_duration_seconds = question_duration
    )

    # Update session duration
    update_session_duration(
      self$con,
      self$session_id,
      elapsed(self$session_start_time)
    )

    # Check if retry needed
    if (!answered_clearly && self$retry_count < self$config$tries) {
      self$retry_count <<- self$retry_count + 1
      increment_retry(self$con, self$session_id)
      self$processing <<- FALSE
      return(list(message = self$messages$retry, complete = FALSE))
    }

    # Store response data
    self$responses[[field_name]] <<- extracted_data[[field_name]]
    self$responses[[paste0(field_name, "_raw")]] <<- user_input
    self$responses[[paste0(
      field_name,
      "_answered_clearly"
    )]] <<- answered_clearly
    self$retry_count <<- 0

    # Move to next question
    self$q_num <<- self$q_num + 1

    # Reset question start time for next question
    self$question_start_time <<- Sys.time()

    # Check if survey complete
    if (self$q_num > length(self$questions)) {
      complete_session(
        self$con,
        self$session_id,
        elapsed(self$session_start_time)
      )
      completion_message <- interpolate(
        self$messages$completion,
        self$responses
      )
      self$processing <<- FALSE
      return(list(message = completion_message, complete = TRUE))
    }

    # Get next question and generate content
    next_q <- self$questions[[self$q_num]]
    generated_content <- self$generate_content(next_q)

    # Handle failed adaptive questions
    if (
      is.null(generated_content) &&
        !is.null(next_q$content) &&
        next_q$content == "follow_up"
    ) {
      # Skip to next question
      self$q_num <<- self$q_num + 1
      self$question_start_time <<- Sys.time()

      if (self$q_num > length(self$questions)) {
        complete_session(
          self$con,
          self$session_id,
          elapsed(self$session_start_time)
        )
        completion_message <- interpolate(
          self$messages$completion,
          self$responses
        )
        self$processing <<- FALSE
        return(list(message = completion_message, complete = TRUE))
      }

      fallback_q <- self$questions[[self$q_num]]
      fallback_message <- personalize_text(fallback_q$text, self$responses)
      self$processing <<- FALSE
      return(list(message = fallback_message, complete = FALSE))
    }

    # Store adaptive question text for database
    if (!is.null(generated_content) && next_q$content == "follow_up") {
      self$responses$adaptive_question_text <<- generated_content
    }

    # Build and return final message
    message <- self$build_message(next_q, generated_content)
    self$processing <<- FALSE
    list(message = message, complete = FALSE)
  }

  # Generate content for question
  self$generate_content <- function(question) {
    if (is.null(question$content)) {
      return(NULL)
    }

    template_config <- self$content[[question$content]]

    # The prompt declares the fields it needs. Keep missing fields as NULL so
    # interpolate() falls back instead of dropping them and misaligning names.
    required_fields <- extract_variables(template_config$prompt)
    context_data <- stats::setNames(
      lapply(required_fields, \(field) self$responses[[field]]),
      required_fields
    )

    tryCatch(
      {
        generate_content(self$chat, template_config, context_data)
      },
      error = function(err) {
        cli::cli_alert_warning(
          "Content generation failed for {question$content}"
        )
        NULL
      }
    )
  }

  # Build message for question
  self$build_message <- function(question, generated_content = NULL) {
    question_text <- personalize_text(question$text, self$responses)

    if (!is.null(generated_content) && !is.null(question$content)) {
      template_config <- self$content[[question$content]]

      if (question$content == "follow_up") {
        # For adaptive questions, return the generated content directly
        return(generated_content)
      } else if (!is.null(template_config$intro)) {
        # For other content types, combine with intro template
        intro_data <- c(
          list(
            content = generated_content,
            next_question = question_text
          ),
          self$responses
        )
        return(interpolate(template_config$intro, intro_data))
      }
    }

    question_text
  }

  # Return the survey instance
  class(self) <- "Survey"
  self
}
