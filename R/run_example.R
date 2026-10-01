#' Run an example survey
#'
#' Starts an example app that ships with the package. The `"icecream"` example
#' is the web page of an ice cream shop with a flavor survey in a side panel.
#' It stores the answers with RSQLite. You choose the model with `chat`, or
#' with the environment variable `SURVEYCHAT_CHAT`. The model must support
#' structured output.
#'
#' @param name The name of the example. Call `run_example(NULL)` to list the
#'   names.
#' @param chat The chat that asks the questions. One of three forms:
#'   * `NULL` (default): the value of the environment variable
#'     `SURVEYCHAT_CHAT`. It is an error if the variable is not set.
#'   * A string, `"provider/model"` or `"provider"`, for [ellmer::chat()].
#'     The provider reads its own key variable, such as `OPENAI_API_KEY`.
#'   * An ellmer chat object, such as [ellmer::chat_openai()].
#' @param ... Other arguments for [shiny::runApp()].
#' @return The names of the examples if `name` is `NULL`. Otherwise, no
#'   value; the app runs until you stop it.
#' @export
#' @examples
#' run_example(NULL)
#' @examplesIf interactive()
#' run_example("icecream", chat = "anthropic/claude-haiku-4-5")
#' run_example("icecream", chat = "openai/gpt-4.1-mini")
#' run_example("icecream", chat = "ollama/llama3.2")
run_example <- function(name = "icecream", chat = NULL, ...) {
  examples <- list.files(system.file("examples", package = "surveychat"))
  if (is.null(name)) {
    return(examples)
  }
  check_string(name)
  if (!name %in% examples) {
    cli::cli_abort(c(
      "There is no example named {.val {name}}.",
      "i" = "The examples are {.or {.val {examples}}}."
    ))
  }
  rlang::check_installed("RSQLite", "to run the example.")
  chat <- example_chat(chat)
  setup_error <- chat_setup_error(chat)
  if (!is.null(setup_error)) {
    cli::cli_abort(
      c(
        "The chat is not set up.",
        "i" = "Check the credentials of the provider, such as its API key in {.file ~/.Renviron}, then restart R."
      ),
      parent = setup_error
    )
  }
  old <- options(surveychat.example_chat = chat)
  on.exit(options(old))
  shiny::runApp(
    system.file("examples", name, package = "surveychat"),
    ...
  )
}

# Returns an ellmer chat. `NULL` reads SURVEYCHAT_CHAT; it is an error if that
# is not set. A
# string goes to ellmer::chat(); a bad provider keeps the ellmer error as the
# parent. A chat object passes through. Any other value is an error.
example_chat <- function(chat, call = rlang::caller_env()) {
  if (is.null(chat)) {
    chat <- Sys.getenv("SURVEYCHAT_CHAT")
    if (!nzchar(chat)) {
      cli::cli_abort(
        c(
          "No chat is set for the example.",
          "i" = "Set {.arg chat}, such as {.code chat = \"openai/gpt-4.1-mini\"}, or set the environment variable {.envvar SURVEYCHAT_CHAT}."
        ),
        call = call
      )
    }
  }
  if (inherits(chat, "Chat")) {
    return(chat)
  }
  if (
    !is.character(chat) || length(chat) != 1 || is.na(chat) || !nzchar(chat)
  ) {
    cli::cli_abort(
      c(
        "{.arg chat} must be a string, an ellmer chat, or {.code NULL}.",
        "i" = "A string is {.val provider/model} or {.val provider}.",
        "x" = "You supplied {.obj_type_friendly {chat}}."
      ),
      call = call
    )
  }
  rlang::try_fetch(
    ellmer::chat(chat, echo = "none"),
    error = function(cnd) {
      cli::cli_abort(
        "Could not make a chat from {.val {chat}}.",
        parent = cnd,
        call = call
      )
    }
  )
}
