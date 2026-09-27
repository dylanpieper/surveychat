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
  locked = NULL
)
```

## Arguments

- spec:

  A survey spec from
  [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md).

- welcome:

  The first message of the survey.

- retry:

  The message when an answer is not valid.

- completion:

  The message after the last answer. It can use `{id}` placeholders for
  any answer.

- closed:

  The text that replaces the chat input after the survey.

- locked:

  The text that replaces the chat input when the chat is not set up, for
  example when the API key is missing.

## Value

`spec` with the new messages.

## Examples

``` r
survey_spec() |>
  set_messages(welcome = "Hi! Three quick questions.")
#> <surveychat_spec> version "1.0", 0 questions
```
