# Set the messages of a survey spec

Each argument is optional. The call changes only the messages that it
names, and the other messages keep their current values.

## Usage

``` r
set_messages(
  spec,
  welcome = NULL,
  retry = NULL,
  completion = NULL,
  closed = NULL,
  locked = NULL,
  suggested = NULL,
  skipped = NULL,
  date = NULL
)
```

## Arguments

- spec:

  A survey spec from
  [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md).

- welcome:

  The first message of the survey.

- retry:

  The message when an answer is not valid and the LLM gives no hint. The
  extraction asks the LLM for a short hint that tells the user what to
  change, and the survey shows the hint if there is one.

- completion:

  The message after the last answer. It can use `{id}` placeholders for
  any answer. It can also be a
  [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
  with a `format`: the LLM writes `{content}` from the answers, such as
  a short reflection on what the user said, and the format places it.
  The LLM gets every answer of the session for this call. If the
  generation fails, the survey shows the format without the content.

- closed:

  The text that replaces the chat input after the survey.

- locked:

  The text that covers the chat when the survey cannot start: the API
  key is missing, or the model does not answer when the chat opens.

- suggested:

  The note before choices that the LLM writes. See the `choices`
  argument of
  [`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md).

- skipped:

  The text that the chat transcript shows for an optional question that
  the user skipped in the form.

- date:

  The message when a chat reply to a date question does not give a full
  date. See the `input` argument of
  [`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md).

## Value

`spec` with the new messages.

## Examples

``` r
survey_spec() |>
  set_messages(welcome = "Hi! Three quick questions.")
#> <surveychat_spec> version "1.0", 0 questions
```
