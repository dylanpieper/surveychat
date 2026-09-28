#' Run an example survey
#'
#' Starts an example app that ships with the package. The `"icecream"` example
#' is the web page of an ice cream shop with a flavor survey in a side panel.
#' It uses [ellmer::chat_claude()], so it needs `ANTHROPIC_API_KEY`, and it
#' stores the answers with RSQLite.
#'
#' @param name The name of the example. Call `run_example(NULL)` to list the
#'   names.
#' @param ... Other arguments for [shiny::runApp()].
#' @return The names of the examples if `name` is `NULL`. Otherwise, no
#'   value; the app runs until you stop it.
#' @export
#' @examples
#' run_example(NULL)
#' @examplesIf interactive()
#' run_example("icecream")
run_example <- function(name = "icecream", ...) {
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
  shiny::runApp(
    system.file("examples", name, package = "surveychat"),
    ...
  )
}
