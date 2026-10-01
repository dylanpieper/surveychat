# Put the survey card in any page

`survey_panel_ui()` is a card with the title, the progress cue, the
chat, and the form. With one method in `set_config(methods = )`, the
card shows that view. With both, it starts side by side, and the header
has three icon buttons: side by side, the form, and the AI chat. On a
narrow screen, the side-by-side view puts the chat below the form. Pair
it with
[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
with the same `id`.

## Usage

``` r
survey_panel_ui(id, title = NULL)
```

## Arguments

- id:

  The module id. It must be the same in the UI and the server.

- title:

  The title in the card header, or `NULL` for no title. With no title,
  the view buttons are on the left and the progress cue on the right.

## Value

A
[`bslib::card()`](https://rstudio.github.io/bslib/reference/card.html).

## Details

The card fills its container. In a page that does not fill the window,
put it in a
[`bslib::as_fill_carrier()`](https://rstudio.github.io/bslib/reference/as_fill_carrier.html)
with a height.

## See also

[`survey_chat_ui()`](https://dylanpieper.github.io/surveychat/reference/survey_chat_ui.md)
for the chat alone. The `"demographics"` example of
[`run_example()`](https://dylanpieper.github.io/surveychat/reference/run_example.md)
puts the card in a narrow page.

## Examples

``` r
if (FALSE) { # interactive() && rlang::is_installed("RSQLite")
library(shiny)
library(bslib)

ui <- page_fixed(
  as_fill_carrier(div(
    style = "max-width: 640px; height: 80vh; margin: 2rem auto;",
    survey_panel_ui("survey")
  ))
)
}
```
