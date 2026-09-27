# Describe text for the LLM to generate

Use `prompt_llm()` for `text` in
[`add_question()`](https://dylanpieper.github.io/surveychat/reference/add_question.md)
to make an adaptive question, or for `intro` to put generated content
before a question.

## Usage

``` r
prompt_llm(prompt, format = NULL)
```

## Arguments

- prompt:

  The prompt for the LLM. It can use `{id}` placeholders for the answers
  to earlier questions.

- format:

  For `intro` only: a template that places the generated text. It must
  contain `{content}` and can use `{id}` placeholders. The survey puts
  the question after it, with a blank line between.

## Value

A list of class `surveychat_prompt`.

## Examples

``` r
prompt_llm("Share a short fun fact about {flavor} ice cream.")
#> $prompt
#> [1] "Share a short fun fact about {flavor} ice cream."
#> 
#> $format
#> NULL
#> 
#> attr(,"class")
#> [1] "surveychat_prompt"
prompt_llm("Share a fun fact about {flavor}.", format = "Oh! {content}")
#> $prompt
#> [1] "Share a fun fact about {flavor}."
#> 
#> $format
#> [1] "Oh! {content}"
#> 
#> attr(,"class")
#> [1] "surveychat_prompt"
```
