# Run an example survey

Starts an example app that ships with the package. The `"icecream"`
example is the web page of an ice cream shop with a flavor survey in a
side panel. It stores the answers with RSQLite. You choose the model
with `chat`, or with the environment variable `SURVEYCHAT_CHAT`. The
model must support structured output.

## Usage

``` r
run_example(name = "icecream", chat = NULL, ...)
```

## Arguments

- name:

  The name of the example. Call `run_example(NULL)` to list the names.

- chat:

  The chat that asks the questions. One of three forms:

  - `NULL` (default): the value of the environment variable
    `SURVEYCHAT_CHAT`. It is an error if the variable is not set.

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

## Examples

``` r
run_example(NULL)
#> [1] "icecream"
if (FALSE) { # interactive()
run_example("icecream", chat = "anthropic/claude-haiku-4-5")
run_example("icecream", chat = "openai/gpt-4.1-mini")
run_example("icecream", chat = "ollama/llama3.2")
}
```
