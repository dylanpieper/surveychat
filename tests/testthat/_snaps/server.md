# survey_server() locks the survey when the chat is not set up

    Code
      shiny::testServer(survey_server, args = list(survey = test_spec(), chat = fake_chat(),
      con = con), {
        session$flushReact()
        expect_match(as.character(output$footer$html), "not available")
        expect_false(DBI::dbExistsTable(con, "sessions"))
      })
    Condition
      Warning:
      The survey is locked because the chat is not set up.
      i Set the API key of the provider, then restart R.
      Caused by error:
      ! Can't find env var `API_KEY`.

