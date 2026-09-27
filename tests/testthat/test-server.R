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
