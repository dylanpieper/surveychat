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
  methods = NULL
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

  Whether a reply can answer later questions. If `TRUE`, the LLM also
  extracts clear answers to later fixed questions, and the survey
  records them and does not ask those questions. Adaptive questions are
  always asked. In the database, such an answer has no `question_text`,
  and `answer_raw` is the reply that gave it.

- check_model:

  Whether the server sends the model a short test prompt when the chat
  opens. If `TRUE`, a spinner covers the chat until the model answers,
  and a failed request locks the survey with the `locked` message of
  [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md).
  The request has one try. A success serves every session that opens in
  the next 5 minutes, so most sessions add no request. A failure serves
  the sessions of the next 5 seconds. If `FALSE`, the survey starts at
  once with no extra request.

- methods:

  How the user answers: `"chat"`, `"form"`, or both. The form shows one
  question at each step with a Shiny input. A fixed choice needs no LLM
  call. Typed text, and any answer to a question with its own `valid`
  rule, gets the same LLM check as the chat. With both, the survey
  starts with the form and the AI chat side by side, and three icon
  buttons in the header change the view at any question. The database
  records the `methods` offered in each session and the `method` of each
  answer. The form needs
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
