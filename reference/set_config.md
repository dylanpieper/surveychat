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
  valid = NULL
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

## Value

`spec` with the new config.

## Examples

``` r
survey_spec() |>
  set_config(tries = 3, character_delay = 0)
#> <surveychat_spec> version "1.0", 0 questions
```
