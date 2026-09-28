# surveychat

surveychat collects data in a conversation with
[shinychat](https://posit-dev.github.io/shinychat/). The user answers
structured questions in a natural dialogue. At the same time, the LLM
extracts the data, generates content, and asks adaptive questions.

## Installation

``` r

pak::pak("dylanpieper/surveychat")
```

## Example 🍦✨

The package includes a demo that collects the ice cream preferences of
the user. The demo uses
[`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
which reads `ANTHROPIC_API_KEY`, and it writes the answers to
`survey.db` in the working directory. Put the key in `~/.Renviron`
(`usethis::edit_r_environ()`) and restart R.

``` r

surveychat::run_example("icecream")
```

The source of the demo is in
[`inst/examples/icecream/app.R`](https://github.com/dylanpieper/surveychat/blob/main/inst/examples/icecream/app.R).
Copy it to start your own survey.

## Key Features

- **LLM extraction** with structured schemas that validate and retry
  invalid answers
- **Adaptive questions** that the LLM writes from the earlier answers of
  the user
- **Generated content**, such as a fun fact, before a question
- **SQL storage** of raw and extracted answers, retry counts, and
  timings
- **Chat UI** with simulated typing, a progress cue, and a closing
  message

## Usage

Build a survey with the pipe. Each verb adds to a plain list:

``` r

library(surveychat)
library(ellmer)

survey <- survey_spec() |>
  add_question(
    "name",
    text = "What's your name?",
    answer = type_string("The person's first name")
  ) |>
  add_question(
    "flavor",
    text = "Hi {name}! What's your favorite ice cream flavor?",
    answer = type_string("The flavor"),
    valid = "they mentioned any flavor"
  ) |>
  add_question(
    "why",
    text = prompt_llm("{name} likes {flavor}. Ask why, in one short question."),
    answer = type_string("The reason"),
    intro = prompt_llm(
      "Share a short fun fact about {flavor} ice cream.",
      format = "Oh, {flavor}! {content}"
    )
  )
```

Then run it in Shiny with any ellmer chat and any DBI connection:

``` r

library(shiny)

chat <- chat_claude(echo = "none")
con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
onStop(\() DBI::dbDisconnect(con))

ui <- survey_ui("survey", title = "Ice cream")
server <- function(input, output, session) {
  survey_server("survey", survey, chat, con)
}
shinyApp(ui, server)
```

Each question has up to four parts:

| Argument | Purpose |
|----|----|
| `text` | The question. `{id}` fills in an earlier answer. With [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md), the LLM writes an adaptive question. |
| `answer` | The ellmer type to extract. |
| `valid` | A plain condition, such as `"they mentioned any flavor"`. An invalid answer is asked again, up to `tries` times. |
| `intro` | A [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md) whose output comes before the question, such as a fun fact. `format` places the output as `{content}`. The intro adds to the question and does not replace it. |

Use
[`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md)
to change the welcome, retry, and closing messages, and
[`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md)
to change the retries and the typing speed.

[Design a
survey](https://dylanpieper.github.io/surveychat/articles/design-surveys.html)
explains validation, placeholders, generated content, and the supported
databases.

## Data Model

**`sessions`**: one row for each user.

| Column | Meaning |
|----|----|
| `session_id` | Generated key |
| `started_at`, `completed_at` | Times of the start and the completion |
| `completed` | `TRUE` after the last answer |
| `retry_count` | Total retries in the session |
| `question_set_version` | `version` from [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md) or [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md) |
| `duration_seconds` | Time since the start, updated after each answer |

**`responses`**: one row for each answer, including each retry.

| Group    | Columns                                                      |
|----------|--------------------------------------------------------------|
| Keys     | `response_id`, `session_id`, `question_id`, `question_order` |
| Exchange | `question_text`, `answer_raw`, `answer_extracted`            |
| Quality  | `valid`, `retry_attempt`                                     |
| Timing   | `responded_at`, `duration_seconds`                           |

## Analyze the Data

The tables are plain SQL, so any DBI client can read them:

``` r

con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
sessions <- DBI::dbReadTable(con, "sessions")
responses <- DBI::dbReadTable(con, "responses")
DBI::dbDisconnect(con)
```
