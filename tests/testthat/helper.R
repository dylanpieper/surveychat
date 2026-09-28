# A chat with the interface that surveychat uses. Each chat_structured() call
# returns the next scripted reply; a reply that is a condition is thrown.
# `$log$prompts` records each prompt and `$log$types` each schema.
fake_chat <- function(...) {
  replies <- list(...)
  log <- new.env()
  log$prompts <- character()
  log$types <- list()
  chat <- structure(
    list(
      log = log,
      clone = function() chat,
      set_turns = function(turns) chat,
      chat_structured = function(prompt, type) {
        log$prompts <- c(log$prompts, prompt)
        log$types <- c(log$types, list(type))
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

# Records each message the server streams and each drawer update, with no
# real stream or browser. Returns a function that gives the messages;
# `drawer = TRUE` gives the drawer calls as `list(type, content)`.
local_sent_messages <- function(env = parent.frame()) {
  log <- new.env()
  log$messages <- character()
  log$drawer <- list()
  testthat::local_mocked_bindings(
    bot_response = function(message, ...) {
      log$messages <- c(log$messages, message)
      message
    },
    .env = env
  )
  record_drawer <- function(type) {
    function(id, content = NULL, ...) {
      log$drawer <- c(log$drawer, list(list(type = type, content = content)))
      invisible()
    }
  }
  testthat::local_mocked_bindings(
    chat_append = function(id, response, ...) {
      force(response)
      promises::promise_resolve(NULL)
    },
    chat_drawer_update = record_drawer("update"),
    chat_drawer_toggle = record_drawer("toggle"),
    .package = "shinychat",
    .env = env
  )
  function(drawer = FALSE) {
    if (drawer) log$drawer else log$messages
  }
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
