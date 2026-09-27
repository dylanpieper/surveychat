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

# Returns NULL if the chat can authenticate, or the error if it cannot. It
# calls the provider's credentials function, which reads the key from the
# environment and makes no API call. A chat with no provider counts as ready.
chat_setup_error <- function(chat) {
  credentials <- tryCatch(
    chat$get_provider()@credentials,
    error = function(err) NULL
  )
  if (!is.function(credentials)) {
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
