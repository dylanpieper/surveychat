# Design a survey

``` r

library(surveychat)
library(ellmer)
```

A survey spec is a plain list of `questions`, `messages`, and `config`.
You build it with the pipe, and the order of the
[`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md)
calls is the order of the survey. This article explains the parts of a
question and what the survey does when the LLM fails.

## Validation

Each question has an `answer` type and a `valid` condition. One LLM call
extracts the answer and checks it against the condition:

``` r

survey <- survey_spec() |>
  add_question(
    "flavor",
    text = "What's your favorite ice cream flavor?",
    answer = type_string("The flavor"),
    valid = "they mentioned any flavor"
  )
```

Write `valid` as a plain condition, without TRUE or FALSE. The package
makes the instruction for the LLM from it, and the extraction prompt
includes the question, so the condition has its context.

When an answer is not valid:

1.  The survey sends the retry message and asks again.
2.  After `tries` retries (default 2), the survey keeps the answer and
    continues. Thus, a user cannot stop the survey with a bad answer.
3.  Each attempt is a row in `responses`, with its `valid` flag and
    `retry_attempt`.

A question with no `valid` uses a default condition: the reply answers
the question, even if it is brief or informal. `set_config(valid = )`
changes the default for the questions that come after it in the pipe.

## Placeholders

The questions, the prompts, and the messages use the same `{id}` syntax
for earlier answers. A value at the start of a sentence gets an
uppercase first letter.

For an answer that the user can skip, such as a name from
`type_string(required = FALSE)`, add a fallback after a bar:
`"Hey {name|there}!"` shows “Hey there!” when the user stays anonymous.

[`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md)
warns when a placeholder does not name an earlier question, so a typo
shows before a user sees it:

``` r

survey <- survey |>
  add_question(
    "topping",
    text = "Which topping goes best with {flavr}?",
    answer = type_string("The topping")
  )
#> Warning: Question topping uses placeholder `{flavr}` that does not name an earlier
#> question.
#> ℹ The user will see the raw name. Check the spelling and the order of the
#>   questions.
```

## Generated content

[`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
describes text for the LLM to write. Where you put it decides its role:

| Argument | Result |
|----|----|
| `intro = prompt_llm(prompt, format = )` | Generated text before a fixed question. `format` places it with `{content}`. |
| `text = prompt_llm(prompt)` | An adaptive question that the LLM writes from the earlier answers. |

``` r

survey <- survey_spec() |>
  add_question(
    "flavor",
    text = "What's your favorite ice cream flavor?",
    answer = type_string("The flavor")
  ) |>
  add_question(
    "why",
    text = "What makes {flavor} your favorite?",
    intro = prompt_llm(
      "Share a short fun fact about {flavor} ice cream.",
      format = "Oh, {flavor}! {content}"
    ),
    answer = type_string("The reason")
  ) |>
  add_question(
    "follow_up",
    text = prompt_llm(
      "The user likes {flavor} because: {why}. Ask one curious follow-up question."
    ),
    answer = type_string("The answer to the follow-up question")
  )

survey
#> <surveychat_spec> version "1.0", 3 questions
#> 1. flavor
#> 2. why [intro]
#> 3. follow_up [adaptive]
```

An adaptive question is different for each user, so the database keeps
the text that the user saw in `question_text`.

If a generation fails, the survey gives a warning and continues:

- A failed `intro` shows the question with no intro.
- A failed adaptive question is skipped.

The first question cannot be adaptive, because there are no answers yet
for its prompt.

## Choices

`choices` shows clickable cards below a question. The user can click a
card or type an answer. An enum answer shows its values with no extra
code.

``` r

survey <- survey_spec() |>
  add_question(
    "flavor",
    text = "What's your favorite ice cream flavor?",
    answer = type_string("The flavor")
  ) |>
  add_question(
    "topping",
    text = "Do you add anything to your {flavor}, or keep it plain?",
    answer = type_string("The topping, or 'none'"),
    choices = list(
      prompt_llm("Suggest exactly 2 common toppings for {flavor} ice cream."),
      "Keep it plain"
    )
  )
```

The LLM ideas come after a note that they are from AI
(`set_messages(suggested = )`). The fixed strings follow in their own
list, so they show even if the generation fails.

## Answers given early

Users often answer more than one question at a time, such as “mint chip
in a cone”. The LLM then also extracts clear answers to later fixed
questions, and the survey does not ask them. Adaptive questions are
always asked. Use `set_config(skip_answered = FALSE)` to ask every
question.

## Messages and config

``` r

survey <- survey |>
  set_messages(
    welcome = "Hi! Three quick questions about ice cream.",
    completion = "Thanks! Enjoy your next scoop of {flavor}."
  ) |>
  set_config(tries = 1, character_delay = 0.01)
```

Each call changes only the fields that it names.

| Function | Fields |
|----|----|
| [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md) | `welcome`, `retry`, `completion`, `closed`, `locked`, `suggested` |
| [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md) | `tries`, `response_delay`, `character_delay`, `delay_variance`, `version`, `valid`, `skip_answered`, `check_model` |

The `locked` message covers the chat when the survey cannot start. This
occurs when the chat cannot authenticate, for example when the API key
is missing, or when the model does not answer a short test prompt as the
chat opens, for example after an HTTP error. The server then writes
nothing to the database. To turn off the test prompt and its spinner,
use `set_config(check_model = FALSE)`.

## Databases

[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
takes any DBI connection or a
[`pool::dbPool()`](http://rstudio.github.io/pool/reference/dbPool.md).
The package supports:

- SQLite
- DuckDB
- Postgres
- MySQL and MariaDB

Every statement uses DBI primitives, so the same code runs on each
backend. The differences that are left are in `R/dialect.R`, with one
entry for each driver class:

- the declaration of an auto-incrementing key
- support for a foreign key
- support for `INSERT ... RETURNING`
- the query for the last generated id

A driver with no entry gets ANSI defaults. To add a backend, add an
entry to `R/dialect.R`.
