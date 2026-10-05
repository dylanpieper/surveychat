# Set the config of a survey spec

Each argument is optional. The call changes only the values that it
names.

## Usage

``` r
set_config(
  spec,
  tries = NULL,
  response_delay = NULL,
  character_delay = NULL,
  delay_variance = NULL,
  version = NULL,
  valid = NULL,
  skip_answered = NULL,
  check_model = NULL,
  views = NULL
)
```

## Arguments

- spec:

  A survey spec from
  [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md).

- tries:

  The maximum number of retries for an answer that is not valid. After
  the last retry, the survey keeps the answer and continues.

- response_delay:

  The delay in seconds before the bot starts a message.

- character_delay:

  The delay in seconds between characters of the simulated typing. Use
  `0` for no delay.

- delay_variance:

  The random variation in seconds of `character_delay`.

- version:

  The version of the question set.

- valid:

  The default condition for a valid answer. It applies to each
  [`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md)
  call after this one that has no `valid` of its own.

- skip_answered:

  Whether the survey can leave out questions that the answers already
  cover. If `TRUE`, the LLM also extracts clear answers to later fixed
  questions, and the survey records them and does not ask those
  questions. In the database, such an answer has no `question_text`, and
  `answer_raw` is the reply that gave it. The LLM can also skip an
  adaptive question that the answers already cover. If `FALSE`, the
  survey asks every question.

- check_model:

  Whether the server sends the model a short test prompt when the chat
  opens. If `TRUE`, a spinner covers the chat until the model answers,
  and a failed request locks the survey with the `locked` message of
  [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md).
  The request has one try. A success serves every session that opens in
  the next 5 minutes, so most sessions add no request. A failure serves
  the sessions of the next 5 seconds. If `FALSE`, the survey starts at
  once with no extra request.

- views:

  The views that the user can use, in order: `"chat"`, `"form"`,
  `"side_by_side"`, or more than one. The survey starts with the first
  view. Side by side shows the form and the chat at once, which helps
  most while you build and test a survey. With more than one view, the
  header has one icon button for each view, in the order given, to
  change the view at any question. The form shows one question at each
  step with a Shiny input. A fixed choice needs no LLM call. Typed text,
  and any answer to a question with its own `valid` rule, gets the same
  LLM validation as the chat. The database records the answer `methods`
  that the views offer in each session and the `method` of each answer.
  The form needs
  [`survey_panel_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_panel_ui.md)
  or
  [`survey_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md).

## Value

`spec` with the new config.

## Examples

``` r
survey_spec() |>
  set_config(tries = 3, character_delay = 0)
#> <surveychat_spec> version "1.0", 0 questions
```
