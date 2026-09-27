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
      i Check the credentials of the provider, such as its API key in '~/.Renviron', then restart R.
      Caused by error:
      ! Can't find env var `API_KEY`.

# chat_setup_error() warns when it cannot find the credentials

    Code
      result <- chat_setup_error(chat)
    Condition
      Warning:
      Could not check the credentials of the chat before the survey starts.
      i A missing key will show only when the first reply is processed.
      This warning is displayed once per session.
      Caused by error in `chat$get_provider()@credentials`:
      ! no applicable method for `@` applied to an object of class "list"

