# Add a question to a survey spec

The order of the `add_question()` calls is the order of the survey. The
package builds the extraction schema from `answer` and `valid`: one LLM
call extracts the answer and checks it. If the answer is not valid, the
survey asks again, up to `tries` times (see
[`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md)).

## Usage

``` r
add_question(
  spec,
  id,
  text,
  answer,
  valid = NULL,
  intro = NULL,
  choices = NULL
)
```

## Arguments

- spec:

  A survey spec from
  [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md).

- id:

  The question id. It is the name of the extracted field and the
  `question_id` in the database. It must be a syntactic name.

- text:

  The question as a string, or a
  [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
  for an adaptive question that the LLM writes from the earlier answers.

- answer:

  A scalar ellmer type, such as
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  that describes the answer to extract.

- valid:

  The condition for a valid answer, written without TRUE or FALSE, such
  as `"they mentioned any flavor"`. If `NULL`, the question uses the
  default from
  [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md)
  at the time of this call.

- intro:

  An optional
  [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
  with a `format`. The LLM generates content that the survey shows
  before the question.

- choices:

  Clickable answer cards below the question. `NULL` shows the values of
  an
  [`ellmer::type_enum()`](https://ellmer.tidyverse.org/reference/type_boolean.html)
  and no cards for other types. A character vector shows those choices.
  A
  [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
  makes the LLM write the choices from the earlier answers; the
  `suggested` message of
  [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md)
  tells the user that they are from the LLM. A list of one
  [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
  and strings, such as
  `list(prompt_llm("Suggest 2 toppings"), "No topping")`, always shows
  the strings after the generated choices. The user can also type an
  answer.

## Value

`spec` with the question added at the end.

## Placeholders

`text`, the prompts, and the `format` of `intro` can use `{id}`
placeholders for the answers to earlier questions. A placeholder that
does not name an earlier question gives a warning, because the user
would see the raw name. Use `{id|fallback}` for an answer that the user
can skip, such as an optional name from
`ellmer::type_string(required = FALSE)`: a skipped answer shows
`fallback`.

## Examples

``` r
survey_spec() |>
  add_question(
    "flavor",
    text = "What's your favorite ice cream flavor?",
    answer = ellmer::type_string("The ice cream flavor"),
    valid = "they mentioned any flavor"
  ) |>
  add_question(
    "why",
    text = "What makes {flavor} your favorite?",
    intro = prompt_llm(
      "Share a short fun fact about {flavor} ice cream.",
      format = "Oh, {flavor}! {content}"
    ),
    answer = ellmer::type_string("The reason they like it")
  ) |>
  add_question(
    "follow_up",
    text = prompt_llm(
      "The user likes {flavor} because: {why}. Ask one follow-up question."
    ),
    answer = ellmer::type_string("The answer to the follow-up question")
  )
#> <surveychat_spec> version "1.0", 3 questions
#> 1. flavor [own rule]
#> 2. why [intro]
#> 3. follow_up [adaptive]
```
