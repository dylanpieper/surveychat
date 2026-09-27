# Run an example survey

Starts an example app that ships with the package. The `"icecream"`
example asks about ice cream preferences with
[`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
so it needs `ANTHROPIC_API_KEY`. It writes the answers to `survey.db` in
the working directory with RSQLite.

## Usage

``` r
run_example(name = "icecream", ...)
```

## Arguments

- name:

  The name of the example. Call `run_example(NULL)` to list the names.

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
run_example("icecream")
}
```
