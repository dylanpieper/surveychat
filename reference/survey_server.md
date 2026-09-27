# Run a survey in a Shiny app

`survey_ui()` and `survey_server()` are a Shiny module pair. Give both
the same `id`. The app owns the chat and the connection: it makes them,
passes them in, and closes the connection when it stops.

## Usage

``` r
survey_server(id, survey, chat, con)

survey_ui(id, title = "Survey")
```

## Arguments

- id:

  The module id. It must be the same in the UI and the server.

- survey:

  A survey spec from
  [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md).

- chat:

  An ellmer chat, such as
  [`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html).
  Each LLM call uses a copy with no history, so one chat can serve all
  users.

- con:

  A DBI connection or a
  [`pool::dbPool()`](http://rstudio.github.io/pool/reference/dbPool.md).
  The server makes the tables with
  [`init_database()`](https://dylanpieper.github.io/surveychat/reference/init_database.md)
  if they are not there.

- title:

  The title in the card header.

## Value

`survey_server()` returns no value; it is called for its side effects.

`survey_ui()` returns a full-page Shiny UI with the chat, a progress
cue, and a footer that shows the closing message.

## Examples

``` r
if (FALSE) { # interactive() && rlang::is_installed("RSQLite")
library(shiny)

survey <- survey_spec() |>
  add_question(
    "color",
    text = "What's your favorite color?",
    answer = ellmer::type_string("The color")
  )

chat <- ellmer::chat_claude(echo = "none")
con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
onStop(\() DBI::dbDisconnect(con))

ui <- survey_ui("survey", title = "Colors")
server <- function(input, output, session) {
  survey_server("survey", survey, chat, con)
}
shinyApp(ui, server)
}
```
