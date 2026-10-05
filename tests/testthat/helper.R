# A chat with the interface that surveychat uses. Each chat_structured() call
# returns the next scripted reply; a reply that is a condition is thrown.
# `$log$prompts` records each prompt and `$log$types` each schema. chat()
# answers the start probe with `.probe`; a `.probe` that is a condition is
# thrown. `$log$probes` counts the chat() calls.
fake_chat <- function(..., .probe = "OK") {
  replies <- list(...)
  log <- new.env()
  log$prompts <- character()
  log$types <- list()
  log$probes <- 0
  chat <- structure(
    list(
      log = log,
      clone = function() chat,
      set_turns = function(turns) chat,
      chat = function(...) {
        log$probes <- log$probes + 1
        if (inherits(.probe, "condition")) {
          stop(.probe)
        }
        .probe
      },
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
# `drawer = TRUE` gives the drawer calls as `list(type, content)`,
# `user = TRUE` the user messages that the server adds, and `ui = TRUE` the
# Shiny UI that the server puts in the chat. It also empties the
# model-check cache, because each test that uses it opens a chat.
local_sent_messages <- function(env = parent.frame()) {
  local_probe_cache(env)
  log <- new.env()
  log$messages <- character()
  log$user <- character()
  log$drawer <- list()
  log$ui <- list()
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
    chat_append = function(id, response, role = "assistant", ...) {
      force(response)
      if (role == "user") {
        log$user <- c(log$user, response)
      }
      if (inherits(response, c("shiny.tag", "shiny.tag.list"))) {
        log$ui <- c(log$ui, list(response))
      }
      promises::promise_resolve(NULL)
    },
    chat_drawer_update = record_drawer("update"),
    chat_drawer_toggle = record_drawer("toggle"),
    .package = "shinychat",
    .env = env
  )
  function(drawer = FALSE, user = FALSE, ui = FALSE) {
    if (ui) {
      log$ui
    } else if (drawer) {
      log$drawer
    } else if (user) {
      log$user
    } else {
      log$messages
    }
  }
}

# Empties the shared model-check cache now and at the end of the test, so no
# result carries over between tests.
local_probe_cache <- function(env = parent.frame()) {
  probe_cache$entries <- list()
  withr::defer(probe_cache$entries <- list(), envir = env)
  invisible()
}

# Records the selector of each removeUI() call. Returns a function that gives
# the selectors.
local_removed_ui <- function(env = parent.frame()) {
  log <- new.env()
  log$selectors <- character()
  testthat::local_mocked_bindings(
    removeUI = function(selector, ...) {
      log$selectors <- c(log$selectors, selector)
      invisible()
    },
    .package = "shiny",
    .env = env
  )
  function() log$selectors
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

# The number of matches of `pattern` in `text`; 0 when there is none
count_matches <- function(pattern, text, fixed = FALSE) {
  sum(gregexpr(pattern, text, fixed = fixed)[[1]] > 0)
}

# Runs the event loop until the chat messages in the queue have streamed
flush_chat <- function(timeout = 5) {
  deadline <- Sys.time() + timeout
  while (!later::loop_empty() && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  if (!later::loop_empty()) {
    testthat::fail("The chat messages did not stream before the deadline.")
  }
  invisible()
}
