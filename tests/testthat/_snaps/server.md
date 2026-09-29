# survey_server() continues when the drawer function fails

    Code
      shiny::testServer(survey_server, args = list(survey = test_spec(), chat = chat,
      con = con, drawer = function(answers, complete) stop("bad card")), {
        session$setInputs(chat_greeting_requested = 1)
        session$setInputs(chat_user_input = "Ana")
        expect_match(as.character(output$progress$html), "Question 2 of 3")
      })
    Condition
      Warning:
      The survey could not fill the drawer.
      Caused by error in `drawer()`:
      ! bad card

# survey_server() checks the drawer function

    Code
      survey_server("survey", test_spec(), fake_chat(), local_sqlite(), drawer = "card")
    Condition
      Error in `survey_server()`:
      ! `drawer` must be `NULL` or a function, not a string.
      i The function takes `answers` and `complete` and returns UI.

# survey_server() locks the survey when the chat is not set up

    Code
      shiny::testServer(survey_server, args = list(survey = test_spec(), chat = fake_chat(),
      con = con), {
        session$flushReact()
        expect_match(as.character(output$footer$html), "unavailable")
        expect_false(DBI::dbExistsTable(con, "sessions"))
      })
    Condition
      Warning:
      The survey is locked because the chat is not set up.
      i Check the credentials of the provider, such as its API key in '~/.Renviron', then restart R.
      Caused by error:
      ! Can't find env var `API_KEY`.

# survey_server() locks the survey when the model does not answer

    Code
      shiny::testServer(survey_server, args = list(survey = test_spec(), chat = chat,
      con = con), {
        session$setInputs(chat_greeting_requested = 1)
        expect_match(as.character(output$footer$html), "unavailable")
        expect_length(sent(), 0)
        expect_false(DBI::dbExistsTable(con, "sessions"))
        session$setInputs(chat_user_input = "Ada")
        expect_length(sent(), 0)
      })
    Condition
      Warning:
      The survey is locked because the model did not answer.
      i Check the status of the provider and the model name.
      Caused by error:
      ! HTTP 529 Overloaded.

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

