# Design a survey

``` r

library(surveychat)
library(ellmer)
```

This article shows how to build and run a survey with surveychat.

The design starts with a survey spec, or a plain list of `questions`,
`messages`, and `config`. You build it with the pipe, and the order of
the
[`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md)
calls is the order of the survey.

## Get started

``` r

survey <- survey_spec() |>
  set_config(views = c("chat", "form")) |>
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

[`survey_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
is a full page. To put the survey in a larger app, use
[`survey_panel_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_panel_ui.md),
a card for any page. For the chat alone, use
[`survey_chat_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_chat_ui.md),
for example in a `bslib::sidebar(fillable = TRUE)`. A chat survey starts
when the chat first shows on the screen, and a survey with the form
starts when the page loads.

Each question has up to six parts:

| Argument | Purpose |
|----|----|
| `text` | The question. `{id}` fills in an earlier answer. With [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md), the LLM writes an adaptive question. |
| `answer` | The ellmer type to extract. |
| `valid` | A plain condition, such as `"they mentioned any flavor"`. An invalid answer is asked again, up to `tries` times. |
| `intro` | A [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md) whose output comes before the question, such as a fun fact. `format` places the output as `{content}`. |
| `choices` | Choices to pick: strings, a [`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md) for LLM ideas, or a list of both. An enum answer gives its values. |
| `when` | A rule on earlier answers, such as `~ age >= 18`. The survey asks the question only when the rule is `TRUE`. |

- Use
  [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md)
  to change the welcome, retry, and closing messages, and
  [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md)
  to change the views, the retries, and the typing speed.
- Use `set_config(views =)` to pick the views and their order: `chat`,
  `form`, or `side_by_side`. The survey starts with the first view.

## Validation

Each question has an `answer` type and a `valid` condition. One LLM call
extracts the answer and validates it against the condition:

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

1.  The survey asks again. The same LLM call writes a short hint that
    tells the user what to change, such as “Please enter your age in
    years.” If there is no hint, the survey sends the `retry` message of
    [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md).
2.  After `tries` retries (default 2), the survey keeps the answer and
    continues. Thus, a user cannot stop the survey with a bad answer.
3.  Each attempt is a row in `responses`, with its `valid` flag and
    `retry_attempt`.

A question with no `valid` argument uses generic logic: the reply
answers the question, even if it is brief or informal.
`set_config(valid = )` changes the default for the questions that come
after it in the pipe.

## Placeholders

The questions, the prompts, and the messages use the same `{id}` syntax
for earlier answers. For an answer that the user can skip, such as a
name from `type_string(required = FALSE)`, add a fallback after a bar:
`"Hey {name|there}!"` shows “Hey there!” when the user stays anonymous.

``` r

survey <- survey |>
  add_question(
    "name",
    text = "What's your name? You can skip this.",
    answer = type_string("The person's first name", required = FALSE)
  ) |>
  add_question(
    "topping",
    text = "Hey {name|there}! Which topping goes best with {flavor}?",
    answer = type_string("The topping")
  )
```

## Generated content

[`prompt_llm()`](https://dylanpieper.github.io/surveychat/reference/prompt_llm.md)
describes text for the LLM to write. Where you put it decides its role:

| Argument | Result |
|----|----|
| `intro = prompt_llm(prompt, format =)` | Generated text before a fixed question. `format` places it with `{content}`. |
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
the text that the user saw in `question_text`. It fills a gap: the LLM
sees all the answers so far and skips the question when they already
tell what it would ask, or when no clear, useful question fits. A
skipped question writes no row. The first question cannot be adaptive,
because there are no answers yet for its prompt.

## Choices

`choices` shows buttons below a question, and one click answers it. The
form and the chat show the same buttons. The user can also type another
answer: in the chat text box, or in the text box under the buttons in
the form, with Next. An enum shows its values as buttons.

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
(`set_messages(suggested = )`).

## Conditional questions

`when` asks a question only for some users. It is a one-sided formula on
the answers to earlier questions. R evaluates it, so it needs no LLM
call:

``` r

survey <- survey_spec() |>
  add_question(
    "club",
    text = "Do you want to join our flavor club? Members get a free scoop on their birthday.",
    answer = type_boolean("Whether they join the flavor club")
  ) |>
  add_question(
    "birthday",
    text = "What is your date of birth?",
    answer = type_string("The date of birth"),
    input = "date",
    when = ~club
  )
```

A yes or no answer has no room for doubt, so a vague reply, such as
“maybe”, is not valid and the survey asks again. When doubt is a real
answer, give it a value. For example,
`type_enum(c("Yes", "Maybe", "No"))` with
`when = ~ club %in% c("Yes", "Maybe")` asks the next question of the
users who are not sure too.

## Answers given early

Users often answer more than one question at a time, such as “mint chip
in a cone”. The LLM then also extracts clear answers to later fixed
questions, and the survey does not ask them. Adaptive questions are
never answered early; instead, the LLM skips one that the answers
already cover. A question whose `when` rule needs the answer to the
current question is asked as usual. Use
`set_config(skip_answered = FALSE)` to ask every question.

## Form and chat

Some users prefer a plain form, and some questions fit a form better.
The views are flexible. `views` lists the views in order, and the survey
starts with the first one. With one view, the survey shows that view
alone. With more than one, the header has an icon button for each view,
in the same order. Each view shows one question at a time.

``` r

survey_form_first <- survey |>
  set_config(views = c("form", "chat"))

survey_preview <- survey |>
  set_config(views = c("side_by_side", "chat", "form"))
```

The first survey starts with the form and lets the user change to the AI
chat, the reverse of the Get started survey. The two views share one
session and one set of answers, so a user can switch at any question.

The second survey starts with the form and the chat side by side. Side
by side helps most while you build and test a survey: an answer in one
view moves the other on, so you can check both at once.

Each row in `responses` records its `method`: `chat` or `form`. The form
needs
[`survey_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
or
[`survey_panel_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_panel_ui.md),
a card that you can put in any page.
[`survey_chat_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_chat_ui.md)
is the chat alone. `run_example("panel-chat-form")` shows all three
views.

## Input types

Each answer type has its input in the form and in the chat:

| Answer | Chat | Form |
|----|----|----|
| [`type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html) | Text box | Text box |
| [`type_integer()`](https://ellmer.tidyverse.org/reference/type_boolean.html), [`type_number()`](https://ellmer.tidyverse.org/reference/type_boolean.html) | Text box | Number input |
| [`type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html) with `input = "date"` | Date picker and Send | Date picker and Next |
| **Single select** |  |  |
| [`type_enum()`](https://ellmer.tidyverse.org/reference/type_boolean.html) | One-click buttons | One-click buttons |
| [`type_boolean()`](https://ellmer.tidyverse.org/reference/type_boolean.html) | One-click Yes and No buttons | One-click Yes and No buttons |
| [`type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html) with `choices` | One-click buttons | One-click buttons, and a text box with Next for another answer |
| **Multi-select** |  |  |
| `type_array(type_enum())` | Checkboxes and Send | Checkboxes and Next |

A one-click button answers at once, with no Send or Next. The chat text
box always works too. Two of these types fit common forms well:

``` r

survey <- survey_spec() |>
  add_question(
    "toppings",
    text = "Which toppings do you like?",
    answer = type_array(
      type_enum(c("Sprinkles", "Hot fudge", "Nuts", "Fresh fruit")),
      required = FALSE
    )
  ) |>
  add_question(
    "birthday",
    text = "What is your date of birth?",
    answer = type_string("The date of birth"),
    input = "date"
  )
```

- A multi-select, `type_array(type_enum(...))`, shows checkboxes. The
  database stores it as a JSON array, such as `["Sprinkles","Nuts"]`.
  With `required = FALSE`, the user can check nothing, and the answer is
  `NA`.
- `input = "date"` on a string answer shows a date input and stores the
  date as `YYYY-MM-DD`. The chat extraction asks for the same format, so
  a reply such as “May 4, 1990” works. It also gets today’s date for a
  relative reply, such as “next Friday”. Today’s date is the date on the
  server, which can differ from the user’s date.
- The form validates both inputs with no LLM call, unless the question
  has its own `valid` rule.
- The chat shows the same input below the question, so the user does not
  need to type a date or a list.

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

The completion message can also be generated. With
`set_messages(completion = prompt_llm(prompt, format = ))`, the LLM
writes `{content}` from the answers, such as a short reflection on what
the user said, and the format adds the fixed thanks. If the generation
fails, the survey shows the format alone.

| Function | Fields |
|----|----|
| [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md) | `welcome`, `retry`, `completion`, `closed`, `locked`, `suggested`, `skipped`, `date` |
| [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md) | `tries`, `response_delay`, `character_delay`, `delay_variance`, `version`, `valid`, `skip_answered`, `check_model`, `views` |

The `locked` message covers the chat when the survey cannot start. This
occurs when the chat cannot authenticate, for example when the API key
is missing, or when the model does not answer a short test prompt as the
chat opens, for example after an HTTP error. The server then writes
nothing to the database. To turn off the test prompt and its spinner,
use `set_config(check_model = FALSE)`.
