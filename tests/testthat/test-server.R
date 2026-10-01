test_that("survey_server() starts the survey and advances on each reply", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  sent <- local_sent_messages()

  shiny::testServer(
    survey_server,
    args = list(survey = test_spec(), chat = chat, con = con),
    {
      # Nothing starts until the chat shows on the screen
      session$flushReact()
      expect_false(DBI::dbExistsTable(con, "sessions"))
      expect_length(sent(), 0)

      session$setInputs(chat_greeting_requested = 1)
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
        1
      )
      expect_match(as.character(output$progress$html), "Question 1 of 3")

      # The first question follows the welcome after a short delay
      deadline <- Sys.time() + 5
      while (length(sent()) < 2 && Sys.time() < deadline) {
        later::run_now(0.1)
      }
      expect_equal(sent(), c(test_spec()$messages$welcome, "Name?"))

      session$setInputs(chat_user_input = "I'm Ana")
      expect_match(as.character(output$progress$html), "Question 2 of 3")
      expect_match(sent()[3], "Ana, flavor?", fixed = TRUE)
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM responses")$n,
        1
      )
    }
  )
})

test_that("survey_server() removes the waiter after the model answers", {
  con <- local_sqlite()
  local_sent_messages()
  removed <- local_removed_ui()

  shiny::testServer(
    survey_server,
    args = list(survey = test_spec(), chat = fake_chat(), con = con),
    {
      session$flushReact()
      expect_length(removed(), 0)

      session$setInputs(chat_greeting_requested = 1)
      expect_equal(removed(), "#proxy1-waiter")
    }
  )
})

test_that("survey_server() skips the model check when it is off", {
  con <- local_sqlite()
  local_sent_messages()
  removed <- local_removed_ui()
  survey <- set_config(test_spec(), check_model = FALSE)
  chat <- fake_chat(.probe = simpleError("The check must not run."))

  shiny::testServer(
    survey_server,
    args = list(survey = survey, chat = chat, con = con),
    {
      session$flushReact()
      expect_equal(removed(), "#proxy1-waiter")

      session$setInputs(chat_greeting_requested = 1)
      expect_equal(removed(), "#proxy1-waiter")
      expect_null(output$footer)
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
        1
      )
    }
  )
})

test_that("survey_server() fills the closed drawer with each new answer", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE),
    list(name = "Ana", valid = TRUE),
    list(content = "x"),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why?"),
    list(why = "fresh", valid = TRUE)
  )
  sent <- local_sent_messages()
  scoop_card <- function(answers, complete) {
    paste(c(names(answers), if (complete) "done"), collapse = ",")
  }

  shiny::testServer(
    survey_server,
    args = list(
      survey = test_spec(),
      chat = chat,
      con = con,
      drawer = scoop_card
    ),
    {
      session$setInputs(chat_greeting_requested = 1)
      # A reply that is not valid adds no answer, so the drawer stays empty
      session$setInputs(chat_user_input = "hmm")
      expect_length(sent(drawer = TRUE), 0)
      expect_equal(output$drawer_ready, "")

      session$setInputs(chat_user_input = "Ana")
      expect_equal(output$drawer_ready, "ready")
      session$setInputs(chat_user_input = "mint")
      session$setInputs(chat_user_input = "fresh")
      session$setInputs(drawer_toggle = 1)
    }
  )

  calls <- sent(drawer = TRUE)
  expect_equal(
    vapply(calls, \(call) call$type, character(1)),
    c("update", "update", "update", "toggle")
  )
  expect_equal(
    lapply(calls, \(call) call$content),
    list("name", "name,flavor", "name,flavor,why,done", NULL)
  )
})

test_that("survey_server() continues when the drawer function fails", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  sent <- local_sent_messages()

  expect_snapshot(
    shiny::testServer(
      survey_server,
      args = list(
        survey = test_spec(),
        chat = chat,
        con = con,
        drawer = \(answers, complete) stop("bad card")
      ),
      {
        session$setInputs(chat_greeting_requested = 1)
        session$setInputs(chat_user_input = "Ana")
        expect_match(as.character(output$progress$html), "Question 2 of 3")
      }
    )
  )
  expect_length(sent(drawer = TRUE), 0)
})

test_that("survey_server() checks the drawer function", {
  expect_snapshot(
    survey_server(
      "survey",
      test_spec(),
      fake_chat(),
      local_sqlite(),
      drawer = "card"
    ),
    error = TRUE
  )
})

test_that("survey_server() locks the survey when the chat is not set up", {
  con <- local_sqlite()
  local_mocked_bindings(
    chat_setup_error = \(chat) simpleError("Can't find env var `API_KEY`.")
  )
  removed <- local_removed_ui()

  expect_snapshot(
    shiny::testServer(
      survey_server,
      args = list(survey = test_spec(), chat = fake_chat(), con = con),
      {
        session$flushReact()
        expect_match(as.character(output$footer$html), "unavailable")
        expect_false(DBI::dbExistsTable(con, "sessions"))
      }
    )
  )
  expect_equal(removed(), "#proxy1-waiter")
})

test_that("survey_server() locks the survey when the model does not answer", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  removed <- local_removed_ui()
  chat <- fake_chat(.probe = simpleError("HTTP 529 Overloaded."))

  expect_snapshot(
    shiny::testServer(
      survey_server,
      args = list(survey = test_spec(), chat = chat, con = con),
      {
        session$setInputs(chat_greeting_requested = 1)
        expect_match(as.character(output$footer$html), "unavailable")
        expect_length(sent(), 0)
        expect_false(DBI::dbExistsTable(con, "sessions"))

        session$setInputs(chat_user_input = "Ada")
        expect_length(sent(), 0)
      }
    )
  )
  expect_equal(removed(), "#proxy1-waiter")
})

test_that("chat_probe_error() returns NULL only when the model sends text", {
  expect_null(chat_probe_error(fake_chat()))
  expect_s3_class(
    chat_probe_error(fake_chat(.probe = simpleError("HTTP 500"))),
    "error"
  )
  expect_s3_class(chat_probe_error(fake_chat(.probe = "  ")), "error")
  expect_s3_class(chat_probe_error(fake_chat(.probe = character())), "error")
})

test_that("chat_probe_error() sends one try with a short timeout", {
  seen <- NULL
  chat <- list(
    clone = function() chat,
    set_turns = function(turns) chat,
    chat = function(...) {
      seen <<- options()[c("ellmer_max_tries", "ellmer_timeout_s")]
      "OK"
    }
  )
  withr::local_options(ellmer_max_tries = 3)

  expect_null(chat_probe_error(chat, timeout = 7))
  expect_equal(seen, list(ellmer_max_tries = 1, ellmer_timeout_s = 7))
  expect_equal(getOption("ellmer_max_tries"), 3)
})

test_that("chat_probe_cached() keeps a success longer than a failure", {
  local_probe_cache()
  start <- Sys.time()
  at <- \(seconds) \() start + seconds
  ok <- fake_chat()
  down <- fake_chat(.probe = simpleError("HTTP 529"))

  expect_null(chat_probe_cached(ok, clock = at(0)))
  expect_null(chat_probe_cached(ok, clock = at(290)))
  expect_equal(ok$log$probes, 1)
  expect_null(chat_probe_cached(ok, clock = at(301)))
  expect_equal(ok$log$probes, 2)

  expect_s3_class(chat_probe_cached(down, clock = at(0)), "error")
  expect_s3_class(chat_probe_cached(down, clock = at(3)), "error")
  expect_equal(down$log$probes, 1)
  expect_s3_class(chat_probe_cached(down, clock = at(6)), "error")
  expect_equal(down$log$probes, 2)
})

test_that("chat_probe_cached() starts an entry's age when its check ends", {
  local_probe_cache()
  start <- Sys.time()
  # Each clock() call moves 4 seconds: the lookup, then the end of the check
  ticks <- 0
  clock <- function() {
    ticks <<- ticks + 1
    start + 4 * (ticks - 1)
  }
  down <- fake_chat(.probe = simpleError("HTTP 529"))

  chat_probe_cached(down, clock = clock)
  expect_s3_class(chat_probe_cached(down, clock = \() start + 8), "error")
  expect_equal(down$log$probes, 1)
})

test_that("two sessions with one chat share one model check", {
  con <- local_sqlite()
  local_sent_messages()
  chat <- fake_chat()

  for (i in 1:2) {
    shiny::testServer(
      survey_server,
      args = list(survey = test_spec(), chat = chat, con = con),
      session$setInputs(chat_greeting_requested = 1)
    )
  }
  expect_equal(chat$log$probes, 1)
  expect_equal(
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
    2
  )
})

test_that("chat_setup_error() returns the credentials error, if any", {
  fake_provider <- S7::new_class(
    "fake_provider",
    properties = list(credentials = S7::class_function)
  )
  chat_with <- function(credentials) {
    list(get_provider = function() fake_provider(credentials = credentials))
  }

  expect_null(chat_setup_error(chat_with(\() "key")))
  expect_s3_class(chat_setup_error(chat_with(\() stop("no key"))), "error")
  expect_null(chat_setup_error(fake_chat()))
})

test_that("chat_setup_error() reads credentials from a real ellmer chat", {
  withr::local_envvar(ANTHROPIC_API_KEY = "test-key")
  chat <- ellmer::chat_anthropic(model = "claude-haiku-4-5", echo = "none")

  expect_null(chat_setup_error(chat))
})

test_that("chat_setup_error() warns when it cannot find the credentials", {
  # The warning shows once per R session; verbose makes it show on every run
  withr::local_options(rlib_warning_verbosity = "verbose")
  chat <- list(get_provider = function() list())

  expect_snapshot(result <- chat_setup_error(chat))
  expect_null(result)
})

test_that("a survey with the form starts on load, with no greeting", {
  con <- local_sqlite()
  local_sent_messages()

  for (methods in list("form", c("chat", "form"))) {
    local_probe_cache()
    spec <- test_spec() |> set_config(methods = methods)
    shiny::testServer(
      survey_server,
      args = list(survey = spec, chat = fake_chat(), con = con),
      {
        session$flushReact()
        session$flushReact()
        expect_true(output$view %in% c("form", "both"))
        expect_match(as.character(output$form$html), "Name?", fixed = TRUE)
      }
    )
  }
  expect_equal(
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
    2
  )
})

test_that("a survey with both methods starts side by side", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- test_spec() |> set_config(methods = c("form", "chat"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      # The start after the first flush shows the question on the next one
      session$flushReact()
      session$flushReact()
      expect_equal(output$view, "both")
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
        1
      )
      form <- as.character(output$form$html)
      expect_match(form, 'id="proxy1-form_name"', fixed = TRUE)
      expect_match(form, "Name?", fixed = TRUE)
      expect_match(as.character(output$method$html), "proxy1-view_pick")

      # A later greeting does not start a second session
      session$setInputs(chat_greeting_requested = 1)
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
        1
      )
    }
  )
})

test_that("the user can answer in the form, switch to the chat, and back", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why mint, Ana?"),
    list(why = "fresh", valid = FALSE),
    list(why = "fresh", valid = TRUE)
  )
  spec <- test_spec() |>
    set_config(methods = c("form", "chat")) |>
    set_messages(completion = "**Bye {name}**")

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = chat, con = con),
    {
      session$flushReact()

      # A type error shows under the field and records nothing
      session$setInputs(form_next = 1)
      expect_match(
        as.character(output$form_error$html),
        "answer this question"
      )
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM responses")$n,
        0
      )

      session$setInputs(form_name = " Ana ", form_next = 2)
      expect_null(output$form_error)
      expect_equal(sent(user = TRUE), "Ana")
      expect_match(sent()[length(sent())], "Ana, flavor?", fixed = TRUE)
      expect_match(as.character(output$progress$html), "Question 2 of 3")
      expect_match(as.character(output$form$html), "Ana, flavor?", fixed = TRUE)

      session$setInputs(view_pick = "chat")
      expect_equal(output$view, "chat")
      session$setInputs(chat_user_input = "mint")
      calls <- length(chat$log$prompts)

      session$setInputs(view_pick = "form")
      expect_equal(output$view, "form")
      expect_match(
        as.character(output$form$html),
        "Why mint, Ana?",
        fixed = TRUE
      )
      expect_length(chat$log$prompts, calls)

      # Side by side shows both views; an unknown value changes nothing
      session$setInputs(view_pick = "both")
      expect_equal(output$view, "both")
      session$setInputs(view_pick = "nope")
      expect_equal(output$view, "both")

      # Typed text that the LLM finds not valid shows the retry message
      session$setInputs(form_why = "it is fresh", form_next = 3)
      expect_match(as.character(output$form_error$html), "try again")
      expect_match(as.character(output$form$html), "Why mint, Ana?")

      session$setInputs(form_next = 4)
      # The form shows the completion message as markdown, with the answers
      expect_match(
        as.character(output$form$html),
        "<strong>Bye Ana</strong>",
        fixed = TRUE
      )
      expect_equal(sent(user = TRUE), c("Ana", "it is fresh"))
    }
  )

  responses <- DBI::dbGetQuery(
    con,
    "SELECT question_id, valid, method FROM responses ORDER BY response_id"
  )
  expect_equal(responses$question_id, c("name", "flavor", "why", "why"))
  expect_equal(as.logical(responses$valid), c(TRUE, TRUE, FALSE, TRUE))
  expect_equal(responses$method, c("form", "chat", "form", "form"))
})

test_that("a chat-only survey shows the chat and no method switch", {
  con <- local_sqlite()
  local_sent_messages()

  shiny::testServer(
    survey_server,
    args = list(survey = test_spec(), chat = fake_chat(), con = con),
    {
      session$flushReact()
      expect_equal(output$view, "chat")
      expect_null(output$method)
      expect_false(DBI::dbExistsTable(con, "sessions"))
    }
  )
})
