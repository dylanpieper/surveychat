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
    }
  )
})
