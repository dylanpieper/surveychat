# Put the survey chat in any page

`survey_chat_ui()` is the survey chat alone, for a sidebar, a card, or a
tab of a larger app. Pair it with
[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
with the same `id`. The survey starts when the chat first shows on the
screen, so a closed sidebar does not start a session.

## Usage

``` r
survey_chat_ui(
  id,
  drawer = FALSE,
  progress = TRUE,
  placeholder = "Type your answer...",
  icon_assistant = NULL
)
```

## Arguments

- id:

  The module id. It must be the same in the UI and the server.

- drawer:

  `FALSE` for no drawer, or a
  [`shinychat::chat_drawer()`](https://posit-dev.github.io/shinychat/r/reference/chat_drawer.html)
  for a panel beside the chat. The `drawer` function of
  [`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
  fills it with the answers.

- progress:

  Whether to show the progress cue below the chat input.

- placeholder:

  The placeholder text of the chat input.

- icon_assistant:

  The icon next to the survey messages, or `NULL` for no icon. See
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html).

## Value

A Shiny tag with the chat, the progress cue, and a footer that shows the
closing message.

## See also

The `"icecream"` example of
[`run_example()`](https://dylanpieper.github.io/surveychat/reference/run_example.md)
puts the chat in the sidebar of a shop page.

## Examples

``` r
if (FALSE) { # interactive() && rlang::is_installed("RSQLite")
library(shiny)
library(bslib)

ui <- page_sidebar(
  sidebar = sidebar(
    survey_chat_ui(
      "survey",
      drawer = shinychat::chat_drawer(title = "Answers", open = FALSE)
    ),
    position = "right",
    fillable = TRUE,
    width = 440
  ),
  "The main page content"
)
}
```
