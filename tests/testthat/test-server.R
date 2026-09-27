test_that("survey_server() starts the survey and advances on each reply", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )

  # Record each message the server streams, with no real stream
  sent <- character()
  local_mocked_bindings(bot_response = function(message, ...) {
    sent <<- c(sent, message)
    message
  })
  local_mocked_bindings(
    chat_append = function(id, response, ...) {
      force(response)
      promises::promise_resolve(NULL)
    },
    .package = "shinychat"
  )

  shiny::testServer(
    survey_server,
    args = list(survey = test_spec(), chat = chat, con = con),
    {
      session$flushReact()
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM sessions")$n,
        1
      )
      expect_match(as.character(output$progress$html), "Question 1 of 3")

      # The first question follows the welcome after a short delay
      deadline <- Sys.time() + 5
      while (length(sent) < 2 && Sys.time() < deadline) {
        later::run_now(0.1)
      }
      expect_equal(sent, c(test_spec()$messages$welcome, "Name?"))

      session$setInputs(chat_user_input = "I'm Ana")
      expect_match(as.character(output$progress$html), "Question 2 of 3")
      expect_match(sent[3], "Ana, flavor?", fixed = TRUE)
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM responses")$n,
        1
      )
    }
  )
})

test_that("survey_server() locks the survey when the chat is not set up", {
  con <- local_sqlite()
  local_mocked_bindings(
    chat_setup_error = \(chat) simpleError("Can't find env var `API_KEY`.")
  )

  expect_snapshot(
    shiny::testServer(
      survey_server,
      args = list(survey = test_spec(), chat = fake_chat(), con = con),
      {
        session$flushReact()
        expect_match(as.character(output$footer$html), "not available")
        expect_false(DBI::dbExistsTable(con, "sessions"))
      }
    )
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
  chat <- list(get_provider = function() list())

  expect_snapshot(result <- chat_setup_error(chat))
  expect_null(result)
})
