# Start a survey spec

A survey spec is a plain list with three parts: `questions`, `messages`,
and `config`. Start it with `survey_spec()`, then add to it with the
pipe verbs
[`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md),
[`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md),
and
[`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md).
Each verb returns the same list with one more part, so
[`str()`](https://rdrr.io/r/utils/str.html) shows the full spec.

## Usage

``` r
survey_spec(version = "1.0")
```

## Arguments

- version:

  The version of the question set. The server writes it to each session
  in the database.

## Value

A list of class `surveychat_spec` with no questions, the default
messages, and the default config.

## See also

[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
to run the spec.

## Examples

``` r
survey <- survey_spec(version = "1.0") |>
  add_question(
    "name",
    text = "What's your name?",
    answer = ellmer::type_string("The person's first name")
  ) |>
  add_question(
    "color",
    text = "Hi {name}! What's your favorite color?",
    answer = ellmer::type_string("The color")
  )
survey
#> <surveychat_spec> version "1.0", 2 questions
#> 1. name
#> 2. color
```
