# Argument checks shared by the pipe verbs and the server. Each check returns
# its input invisibly and reports errors against the user-facing caller.

check_string <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!rlang::is_string(x) || is.na(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be a single string, not {.obj_type_friendly {x}}.",
      call = call
    )
  }
  invisible(x)
}

check_number <- function(
  x,
  whole = FALSE,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  ok <- is.numeric(x) && length(x) == 1 && !is.na(x) && x >= 0
  if (ok && whole) {
    ok <- x == round(x)
  }
  if (!ok) {
    what <- if (whole) {
      "a non-negative whole number"
    } else {
      "a non-negative number"
    }
    cli::cli_abort(
      if (is.numeric(x) && length(x) == 1) {
        "{.arg {arg}} must be {what}, not {.val {x}}."
      } else {
        "{.arg {arg}} must be {what}, not {.obj_type_friendly {x}}."
      },
      call = call
    )
  }
  invisible(x)
}

check_bool <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!rlang::is_bool(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be {.code TRUE} or {.code FALSE}, not {.obj_type_friendly {x}}.",
      call = call
    )
  }
  invisible(x)
}

# `FALSE` or a shinychat::chat_drawer() configuration
check_drawer_config <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!isFALSE(x) && !inherits(x, "chat_drawer")) {
    cli::cli_abort(
      "{.arg {arg}} must be {.code FALSE} or a {.fn shinychat::chat_drawer}, not {.obj_type_friendly {x}}.",
      call = call
    )
  }
  invisible(x)
}

# `NULL` or a function of `answers` and `complete`
check_drawer_fn <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!is.null(x) && !is.function(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be {.code NULL} or a function, not {.obj_type_friendly {x}}.",
        "i" = "The function takes {.arg answers} and {.arg complete} and returns UI."
      ),
      call = call
    )
  }
  invisible(x)
}

check_spec <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!inherits(x, "surveychat_spec")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a survey spec, not {.obj_type_friendly {x}}.",
        "i" = "Start the pipe with {.fn survey_spec}."
      ),
      call = call
    )
  }
  invisible(x)
}

check_prompt <- function(
  x,
  arg = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (!inherits(x, "surveychat_prompt")) {
    cli::cli_abort(
      "{.arg {arg}} must be made with {.fn prompt_llm}, not {.obj_type_friendly {x}}.",
      call = call
    )
  }
  invisible(x)
}

check_backends <- function(chat, con, call = rlang::caller_env()) {
  if (!inherits(chat, "Chat")) {
    cli::cli_abort(
      c(
        "{.arg chat} must be an ellmer chat, not {.obj_type_friendly {chat}}.",
        "i" = "Make one with a function such as {.fn ellmer::chat_claude}."
      ),
      call = call
    )
  }
  if (!inherits(con, "DBIConnection") && !inherits(con, "Pool")) {
    cli::cli_abort(
      c(
        "{.arg con} must be a DBI connection or a pool, not {.obj_type_friendly {con}}.",
        "i" = "Make one with {.fn DBI::dbConnect} or {.fn pool::dbPool}."
      ),
      call = call
    )
  }
  invisible(list(chat = chat, con = con))
}

# Returns NULL if the chat's credentials resolve, or the error if they do not.
# It calls the provider's credentials function. For a key-based provider, such
# as Anthropic or OpenAI, this only reads an environment variable. For an OAuth
# or cloud-identity provider, it can request a token over the network. A chat
# with no get_provider() method, such as a test double, counts as ready. An
# ellmer provider without a credentials function gives a warning, so a change
# in ellmer cannot turn the check off without a signal.
chat_setup_error <- function(chat) {
  if (!is.function(chat$get_provider)) {
    return(NULL)
  }
  credentials <- tryCatch(
    chat$get_provider()@credentials,
    error = function(err) err
  )
  if (!is.function(credentials)) {
    cli::cli_warn(
      c(
        "Could not check the credentials of the chat before the survey starts.",
        "i" = "A missing key will show only when the first reply is processed."
      ),
      parent = if (inherits(credentials, "condition")) credentials,
      .frequency = "once",
      .frequency_id = "surveychat_credentials_unchecked"
    )
    return(NULL)
  }
  tryCatch(
    {
      credentials()
      NULL
    },
    error = function(err) err
  )
}

# Returns NULL if the model answers a short prompt with text, or the error if
# it does not. It sends one small request on a copy of the chat with no
# history, so an HTTP error, such as an overloaded or unreachable service,
# shows before the survey starts. The request has one try and a short
# timeout, because it blocks the R process while it runs.
chat_probe_error <- function(chat, timeout = 20) {
  old <- options(ellmer_max_tries = 1, ellmer_timeout_s = timeout)
  on.exit(options(old))
  tryCatch(
    {
      reply <- fresh_chat(chat)$chat("Reply with the word OK.", echo = "none")
      if (!nzchar(trimws(paste(as.character(reply), collapse = "")))) {
        cli::cli_abort("The model returned no text.")
      }
      NULL
    },
    error = function(err) err
  )
}

# Results of chat_probe_error() by chat, shared by all sessions in the process
probe_cache <- new.env(parent = emptyenv())
probe_cache$entries <- list()

# chat_probe_error() with a result that is reused for `ttl` seconds for the
# same chat object. One check then serves every session that opens in that
# time, in a healthy period and in an outage.
chat_probe_cached <- function(chat, ttl = 30, now = Sys.time()) {
  fresh <- Filter(
    \(entry) difftime(now, entry$time, units = "secs") < ttl,
    probe_cache$entries
  )
  for (entry in fresh) {
    if (identical(entry$chat, chat)) {
      probe_cache$entries <- fresh
      return(entry$error)
    }
  }
  error <- chat_probe_error(chat)
  entry <- list(chat = chat, time = now, error = error)
  probe_cache$entries <- c(fresh, list(entry))
  error
}
