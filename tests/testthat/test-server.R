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

  for (views in list("form", c("side_by_side", "chat"))) {
    local_probe_cache()
    spec <- test_spec() |> set_config(views = views)
    shiny::testServer(
      survey_server,
      args = list(survey = spec, chat = fake_chat(), con = con),
      {
        session$flushReact()
        session$flushReact()
        expect_true(output$view %in% c("form", "side_by_side"))
        expect_match(as.character(output$form$html), "Name?", fixed = TRUE)
      }
    )
  }
  expect_equal(
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
    2
  )
})

test_that("a survey starts with its first view", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- test_spec() |> set_config(views = c("side_by_side", "form", "chat"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      # The start after the first flush shows the question on the next one
      session$flushReact()
      session$flushReact()
      expect_equal(output$view, "side_by_side")
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
    set_config(views = c("side_by_side", "form", "chat")) |>
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
      flush_chat()
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
      session$setInputs(view_pick = "side_by_side")
      expect_equal(output$view, "side_by_side")
      session$setInputs(view_pick = "nope")
      expect_equal(output$view, "side_by_side")

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
      # The closed message and its check mark come under the completion
      form <- as.character(output$form$html)
      expect_match(form, "sb-form-completion", fixed = TRUE)
      expect_lt(
        regexpr("Bye Ana", form, fixed = TRUE),
        regexpr(survey_spec()$messages$closed, form, fixed = TRUE)
      )
      flush_chat()
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

test_that("the progress cue counts only the questions that apply", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- survey_spec() |>
    set_config(views = "form", character_delay = 0) |>
    add_question(
      "attending",
      text = "Will you attend?",
      answer = ellmer::type_enum(c("Yes", "No"), "Attending")
    ) |>
    add_question(
      "dinner",
      text = "Dinner?",
      answer = ellmer::type_boolean("Dinner"),
      when = ~ attending == "Yes"
    ) |>
    add_question(
      "size",
      text = "Shirt size?",
      answer = ellmer::type_enum(c("S", "M", "L"), "Size")
    )

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      expect_match(as.character(output$progress$html), "Question 1 of 3")

      session$setInputs(form_pick_attending = "No")
      expect_match(as.character(output$progress$html), "Question 2 of 2")
      expect_match(as.character(output$form$html), "Shirt size?", fixed = TRUE)
    }
  )
})

test_that("the form takes a choice with one click or typed text with Next", {
  con <- local_sqlite()
  local_sent_messages()
  chat <- fake_chat(list(holder = "a waffle", valid = TRUE))
  spec <- survey_spec() |>
    set_config(views = "form", character_delay = 0, check_model = FALSE) |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_string("Serve"),
      choices = c("Cone", "Cup")
    ) |>
    add_question(
      "holder",
      text = "Holder?",
      answer = ellmer::type_string("Holder"),
      choices = c("Plain", "Sugar")
    )

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = chat, con = con),
    {
      session$flushReact()
      session$flushReact()
      calls <- length(chat$log$prompts)
      expect_match(as.character(output$form$html), "Or type your own")
      session$setInputs(form_pick_serve = "Cone")
      expect_length(chat$log$prompts, calls)
      expect_match(as.character(output$form$html), "Holder?", fixed = TRUE)

      # A late click on a choice of the answered question changes nothing
      session$setInputs(form_pick_serve = "Cup")
      expect_match(as.character(output$form$html), "Holder?", fixed = TRUE)

      session$setInputs(form_holder = "a waffle", form_next = 1)
      expect_length(chat$log$prompts, calls + 1)
      flush_chat()
    }
  )
  expect_equal(
    DBI::dbGetQuery(con, "SELECT answer_raw FROM responses")$answer_raw,
    c("Cone", "a waffle")
  )
})

test_that("Skip leaves an optional one-click question with no answer", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- survey_spec() |>
    set_config(views = "form", character_delay = 0, check_model = FALSE) |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_enum(c("Cone", "Cup"), "Serve", required = FALSE)
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      session$flushReact()
      session$setInputs(form_next = 1)
      expect_match(as.character(output$form$html), "End?", fixed = TRUE)
      flush_chat()
    }
  )
  expect_true(is.na(
    DBI::dbGetQuery(
      con,
      "SELECT answer_extracted FROM responses"
    )$answer_extracted
  ))
})

test_that("a fast form answer streams after the first question", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  chat <- fake_chat(list(name = "Ana", valid = TRUE), list(content = "x"))
  spec <- test_spec() |> set_config(views = c("side_by_side", "form", "chat"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = chat, con = con),
    {
      session$flushReact()
      session$flushReact()
      # The user answers before the delayed first question streams
      session$setInputs(form_name = "Ana", form_next = 1)
      flush_chat()
      expect_equal(sent()[1:2], c(spec$messages$welcome, "Name?"))
      expect_match(sent()[3], "Ana, flavor?", fixed = TRUE)
    }
  )
})

test_that("a chat message that fails does not stop the next ones", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  calls <- 0
  local_mocked_bindings(
    chat_append = function(id, response, role = "assistant", ...) {
      force(response)
      calls <<- calls + 1
      if (calls == 1) {
        promises::promise_reject(simpleError("boom"))
      } else {
        promises::promise_resolve(NULL)
      }
    },
    .package = "shinychat"
  )
  spec <- test_spec() |> set_config(views = c("side_by_side", "form", "chat"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      session$flushReact()
      expect_warning(flush_chat(), "could not show a chat message")
      expect_equal(sent(), c(spec$messages$welcome, "Name?"))
    }
  )
})

test_that("a multi-select goes through the form to the chat and the table", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  spec <- survey_spec() |>
    set_config(
      views = c("side_by_side", "form", "chat"),
      character_delay = 0
    ) |>
    add_question(
      "diet",
      text = "Diet?",
      answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      session$flushReact()
      session$setInputs(form_diet = c("Vegan", "Halal"), form_next = 1)
      flush_chat()
      expect_equal(sent(user = TRUE), "Vegan, Halal")
    }
  )
  expect_equal(
    DBI::dbGetQuery(
      con,
      "SELECT answer_extracted FROM responses"
    )$answer_extracted,
    '["Vegan","Halal"]'
  )
})

test_that("a chat-first survey offers the form but not side by side", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- test_spec() |> set_config(views = c("chat", "form"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      session$flushReact()
      expect_equal(output$view, "chat")

      session$setInputs(view_pick = "side_by_side")
      expect_equal(output$view, "chat")
      session$setInputs(view_pick = "form")
      expect_equal(output$view, "form")
    }
  )
})

test_that("the server orders the view buttons by the views", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- test_spec() |> set_config(views = c("chat", "form"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      html <- as.character(output$method$html)
      values <- regmatches(html, gregexpr('value="[a-z_]+"', html))[[1]]
      expect_equal(gsub('value=|"', "", values), c("chat", "form"))
    }
  )
})

test_that("the chat shows a date input and takes its value as an answer", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  spec <- survey_spec() |>
    set_config(character_delay = 0) |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date") |>
    add_question(
      "diet",
      text = "Diet?",
      answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  removed <- local_removed_ui()

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$setInputs(chat_greeting_requested = 1)
      flush_chat()
      ui <- as.character(sent(ui = TRUE)[[1]])
      expect_match(ui, 'id="proxy1-chat_input_day"', fixed = TRUE)
      expect_match(ui, 'id="proxy1-chat_send_day"', fixed = TRUE)

      session$setInputs(
        chat_input_day = as.Date("2026-11-03"),
        chat_send_day = 1
      )
      flush_chat()
      expect_equal(sent(user = TRUE), "2026-11-03")
      expect_true("#proxy1-chat_widget_day" %in% removed())
      expect_match(
        as.character(sent(ui = TRUE)[[2]]),
        "shiny-input-checkboxgroup",
        fixed = TRUE
      )

      session$setInputs(
        chat_input_diet = c("Vegan", "Halal"),
        chat_send_diet = 1
      )
      flush_chat()
      expect_equal(sent(user = TRUE), c("2026-11-03", "Vegan, Halal"))
      expect_equal(sent()[length(sent())], "End?")
    }
  )
  rows <- DBI::dbGetQuery(
    con,
    "SELECT answer_extracted, method FROM responses ORDER BY response_id"
  )
  expect_equal(rows$answer_extracted, c("2026-11-03", '["Vegan","Halal"]'))
  expect_equal(rows$method, c("chat", "chat"))
})

test_that("the chat shows one-click buttons for an enum, a yes or no, and choices", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  spec <- survey_spec() |>
    set_config(character_delay = 0) |>
    add_question(
      "role",
      text = "Role?",
      answer = ellmer::type_enum(c("Student", "Engineer"), "Role")
    ) |>
    add_question(
      "dinner",
      text = "Dinner?",
      answer = ellmer::type_boolean("D")
    ) |>
    add_question(
      "topping",
      text = "Topping?",
      answer = ellmer::type_string("Topping"),
      choices = c("Sprinkles", "None")
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$setInputs(chat_greeting_requested = 1)
      flush_chat()
      expect_match(as.character(sent(ui = TRUE)[[1]]), 'data-value="Engineer"')
      expect_match(as.character(sent(ui = TRUE)[[1]]), "sb-pick", fixed = TRUE)
      session$setInputs(chat_pick_role = "Engineer")
      flush_chat()
      expect_match(as.character(sent(ui = TRUE)[[2]]), 'data-value="TRUE"')
      session$setInputs(chat_pick_dinner = "TRUE")
      flush_chat()
      expect_match(as.character(sent(ui = TRUE)[[3]]), 'data-value="Sprinkles"')
      session$setInputs(chat_pick_topping = "None")
      flush_chat()
      expect_equal(sent(user = TRUE), c("Engineer", "Yes", "None"))
      # No markdown cards in any chat message
      expect_false(any(grepl("suggestion", sent(), fixed = TRUE)))
    }
  )
  rows <- DBI::dbGetQuery(
    con,
    "SELECT answer_extracted, method FROM responses ORDER BY response_id"
  )
  expect_equal(rows$answer_extracted, c("Engineer", "TRUE", "None"))
  expect_equal(rows$method, rep("chat", 3))
})

test_that("a question whose choices failed to generate gets no chat input", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  spec <- survey_spec() |>
    set_config(character_delay = 0) |>
    add_question(
      "topping",
      text = "Topping?",
      answer = ellmer::type_string("Topping"),
      choices = prompt_llm("Toppings")
    )

  shiny::testServer(
    survey_server,
    args = list(
      survey = spec,
      chat = fake_chat(simpleError("API down")),
      con = con
    ),
    {
      suppressWarnings(session$setInputs(chat_greeting_requested = 1))
      flush_chat()
      expect_length(sent(ui = TRUE), 0)
      expect_equal(sent()[length(sent())], "Topping?")
    }
  )
})

test_that("a chat input leaves the chat when the survey moves on another way", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  removed <- local_removed_ui()
  spec <- survey_spec() |>
    set_config(character_delay = 0) |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_enum(c("Cone", "Cup"), "Serve")
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  chat <- fake_chat(list(serve = "Cone", valid = TRUE))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = chat, con = con),
    {
      session$setInputs(chat_greeting_requested = 1)
      flush_chat()
      session$setInputs(chat_user_input = "a cone please")
      flush_chat()
      expect_true("#proxy1-chat_widget_serve" %in% removed())

      # A late click on a choice of the answered question changes nothing
      session$setInputs(chat_pick_serve = "Cup")
      flush_chat()
      expect_equal(
        DBI::dbGetQuery(
          con,
          "SELECT answer_extracted FROM responses"
        )$answer_extracted,
        "Cone"
      )
    }
  )
})

test_that("a chat Send with no pick keeps the input and records nothing", {
  con <- local_sqlite()
  sent <- local_sent_messages()
  removed <- local_removed_ui()
  spec <- survey_spec() |>
    set_config(character_delay = 0) |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_array(ellmer::type_enum(c("Cone", "Cup")))
    )

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$setInputs(chat_greeting_requested = 1)
      flush_chat()
      session$setInputs(chat_send_serve = 1)
      flush_chat()
      expect_match(sent()[length(sent())], "at least one")
      expect_false("#proxy1-chat_widget_serve" %in% removed())
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM responses")$n,
        0
      )
    }
  )
})

test_that("the form shows a generated completion, escaped, then the closed message", {
  con <- local_sqlite()
  local_sent_messages()
  spec <- survey_spec() |>
    set_config(views = "form") |>
    set_messages(
      completion = prompt_llm("Reflect.", format = "{content}\n\nBye {name}")
    ) |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("N"),
      choices = "Ana"
    )
  chat <- fake_chat(list(content = "Nice <b>pick</b>!"))

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = chat, con = con),
    {
      session$flushReact()
      session$flushReact()
      session$setInputs(form_name = "Ana", form_next = 1)
      form <- as.character(output$form$html)
      expect_match(form, "Nice &lt;b&gt;pick&lt;/b&gt;!", fixed = TRUE)
      expect_lt(
        regexpr("Bye Ana", form, fixed = TRUE),
        regexpr(survey_spec()$messages$closed, form, fixed = TRUE)
      )
    }
  )
})

test_that("a chat input leaves the chat after a form answer and at the end", {
  con <- local_sqlite()
  local_sent_messages()
  removed <- local_removed_ui()
  spec <- survey_spec() |>
    set_config(
      views = c("side_by_side", "form", "chat"),
      character_delay = 0
    ) |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_enum(c("Cone", "Cup"), "Serve")
    ) |>
    add_question(
      "size",
      text = "Size?",
      answer = ellmer::type_enum(c("Small", "Large"), "Size")
    )

  shiny::testServer(
    survey_server,
    args = list(survey = spec, chat = fake_chat(), con = con),
    {
      session$flushReact()
      session$flushReact()
      flush_chat()
      session$setInputs(form_pick_serve = "Cone")
      flush_chat()
      expect_true("#proxy1-chat_widget_serve" %in% removed())
      session$setInputs(form_pick_size = "Large")
      flush_chat()
      expect_true("#proxy1-chat_widget_size" %in% removed())
    }
  )
})
