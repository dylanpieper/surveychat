# Run an example survey

Starts an example app that ships with the package and stores the answers
with RSQLite. You choose the model with `chat`, or with the environment
variable `SURVEYCHAT_MODEL`. The model must support structured output.

## Usage

``` r
run_example(name = "chat-sidebar-drawer", chat = NULL, ...)
```

## Arguments

- name:

  The name of the example. Call `run_example(NULL)` to list the names.

- chat:

  The chat that asks the questions. One of three forms:

  - `NULL` (default): the value of the environment variable
    `SURVEYCHAT_MODEL`. It is an error if the variable is not set.

  - A string, `"provider/model"` or `"provider"`, for
    [`ellmer::chat()`](https://ellmer.tidyverse.org/reference/chat-any.html).
    The provider reads its own key variable, such as `OPENAI_API_KEY`.

  - An ellmer chat object, such as
    [`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html).

- ...:

  Other arguments for
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Value

The names of the examples if `name` is `NULL`. Otherwise, no value; the
app runs until you stop it.

## Details

The examples are:

- `"chat-sidebar-drawer"` (default): a chat survey in the sidebar of an
  ice cream shop page, with a drawer for the answers so far. It shows
  generated intros and choices, an adaptive question, answers given
  early, and a flavor club question that leads to a date picker.

- `"panel-chat-form"`: a workshop sign-up in a card that starts in the
  AI chat, with buttons to change to the form or to both side by side.
  It shows a multi-select of workshop days, a Yes, Maybe, or No question
  that leads to a dietary question, plain-language validation, three
  adaptive follow-ups, and a generated closing line.

## Examples

``` r
run_example(NULL)
#> [1] "chat-sidebar-drawer" "panel-chat-form"    
if (FALSE) { # interactive()
run_example("chat-sidebar-drawer", chat = "anthropic/claude-haiku-4-5")
run_example("chat-sidebar-drawer", chat = "openai/gpt-4.1-mini")
run_example("chat-sidebar-drawer", chat = "ollama/llama3.2")
run_example("panel-chat-form", chat = "anthropic/claude-haiku-4-5")
}
```
