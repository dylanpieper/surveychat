test_that("survey_server() starts the survey and advances on each reply", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x")
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

      session$setInputs(chat_user_input = "I'm Ana")
      expect_match(as.character(output$progress$html), "Question 2 of 3")
      expect_equal(
        DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM responses")$n,
        1
      )

      # Run the delayed first question and the streams before the session ends
      deadline <- Sys.time() + 5
      while (!later::loop_empty() && Sys.time() < deadline) {
        later::run_now(0.1)
      }
      expect_true(later::loop_empty())
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
