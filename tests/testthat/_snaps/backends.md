# survey_server() rejects a chat or a connection of the wrong type

    Code
      survey_server("s", test_spec(), chat = list(), con = con)
    Condition
      Error in `survey_server()`:
      ! `chat` must be an ellmer chat, not an empty list.
      i Make one with a function such as `ellmer::chat_claude()`.
    Code
      survey_server("s", test_spec(), chat = fake_chat(), con = "survey.db")
    Condition
      Error in `survey_server()`:
      ! `con` must be a DBI connection or a pool, not a string.
      i Make one with `DBI::dbConnect()` or `pool::dbPool()`.

