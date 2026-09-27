# A chat with the interface that surveychat uses. Each chat_structured() call
# returns the next scripted reply; a reply that is a condition is thrown.
# `$log$prompts` records each prompt.
fake_chat <- function(...) {
  replies <- list(...)
  log <- new.env()
  log$prompts <- character()
  chat <- structure(
    list(
      log = log,
      clone = function() chat,
      set_turns = function(turns) chat,
      chat_structured = function(prompt, type) {
        log$prompts <- c(log$prompts, prompt)
        n <- length(log$prompts)
        if (n > length(replies)) {
          stop("fake_chat has no reply ", n)
        }
        reply <- replies[[n]]
        if (inherits(reply, "condition")) {
          stop(reply)
        }
        reply
      }
    ),
    class = c("fake_chat", "Chat")
  )
  chat
}

local_sqlite <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con), envir = env)
  con
}

local_duckdb <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  con
}

# The backends that every database test runs on
backends <- list(sqlite = local_sqlite, duckdb = local_duckdb)

# Three questions: a fixed one, one with an intro, and an adaptive one
test_spec <- function() {
  survey_spec() |>
    set_messages(completion = "Bye {name}") |>
    set_config(character_delay = 0, tries = 1) |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("Name")
    ) |>
    add_question(
      "flavor",
      text = "{name}, flavor?",
      intro = prompt_llm("Fact about {name}", format = "Hi {name}! {content}"),
      answer = ellmer::type_string("Flavor")
    ) |>
    add_question(
      "why",
      text = prompt_llm("Ask why {name} likes {flavor}"),
      answer = ellmer::type_string("Reason")
    )
}
