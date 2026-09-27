# surveychat 0.1.0

* Initial release as an R package. Build a survey with `survey_spec()`,
  `add_question()`, `prompt_llm()`, `set_messages()`, and `set_config()`, and
  run it with the `survey_ui()` and `survey_server()` Shiny module.

* `survey_server()` locks the survey when the chat cannot authenticate, for
  example when the API key is missing. The input is hidden, the `locked`
  message shows, and nothing is written to the database.

* The `responses` table stores the extraction flag in the column `valid`. A
  database made by the app before the package has the column
  `answered_clearly`: rename that column, or start a new database.
