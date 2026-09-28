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

The package includes a demo: the web page of an ice cream shop with a
flavor survey in a side panel. The survey asks about the favorites of
the user, and a drawer beside the chat shows the answers so far. The
demo uses
[`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
which reads `ANTHROPIC_API_KEY`. Put the key in `~/.Renviron`
(`usethis::edit_r_environ()`) and restart R.

``` r

surveychat::run_example("icecream")
```

![The web page of an ice cream shop. A side panel on the right shows the
flavor survey chat, which asks for the name of the user and shows a card
to stay anonymous.](reference/figures/icecream.png)

The source is in
[`inst/examples/icecream/app.R`](https://github.com/dylanpieper/surveychat/blob/main/inst/examples/icecream/app.R).
Copy it to start your own survey.

## Key Features

- **LLM extraction** with structured schemas that validate and retry
  invalid answers, and that record answers to later questions so the
  survey does not ask again
- **Adaptive questions and generated content** based on the previous
  answers of the user
- **Choice cards** from a fixed list, an enum, or the LLM; the user can
  also type an answer
- **SQL storage** of raw and extracted answers, retry counts, and
  timings
- **Chat UI** as a full page or in any layout, such as a sidebar, with a
  progress cue and an optional drawer for the answers

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

To put the survey in a larger app, use
[`survey_chat_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_chat_ui.md)
in place of
[`survey_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md),
for example in a `bslib::sidebar(fillable = TRUE)`. The survey starts
when the chat first shows on the screen.

Each question has up to five parts:

| Argument | Purpose |
|----|----|
| `text` | The question. `{id}` fills in an earlier answer. With [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md), the LLM writes an adaptive question. |
| `answer` | The ellmer type to extract. |
| `valid` | A plain condition, such as `"they mentioned any flavor"`. An invalid answer is asked again, up to `tries` times. |
| `intro` | A [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md) whose output comes before the question, such as a fun fact. `format` places the output as `{content}`. The intro adds to the question and does not replace it. |
| `choices` | Clickable cards: strings, a [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md) for LLM ideas, or a list of both. An enum answer shows its values. |

Use
[`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md)
to change the welcome, retry, and closing messages, and
[`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md)
to change the retries and the typing speed.

[Design a
survey](https://dylanpieper.github.io/surveychat/articles/design-surveys.html)
explains validation, placeholders, generated content, choices, and the
supported databases.

## Data Model

**`sessions`**: one row for each user.

| Column | Meaning |
|----|----|
| `session_id` | Generated key |
| `started_at`, `completed_at` | Times of the start and the completion |
| `completed` | `TRUE` after the last answer |
| `retry_count` | Total retries in the session |
| `version` | The version of the question set, from [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md) or [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md) |
| `duration_seconds` | Time since the start, updated after each answer |

**`responses`**: one row for each answer, including each retry.

| Group    | Columns                                                      |
|----------|--------------------------------------------------------------|
| Keys     | `response_id`, `session_id`, `question_id`, `question_order` |
| Exchange | `question_text`, `answer_raw`, `answer_extracted`            |
| Quality  | `valid`, `retry_attempt`                                     |
| Timing   | `responded_at`, `duration_seconds`                           |

An answer that came early, in the reply to an earlier question, has no
`question_text`. A skipped optional answer has no `answer_extracted`.

## Analyze the Data

The tables are plain SQL, so any DBI client can read them:

``` r

con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
sessions <- DBI::dbReadTable(con, "sessions")
responses <- DBI::dbReadTable(con, "responses")
DBI::dbDisconnect(con)
```
