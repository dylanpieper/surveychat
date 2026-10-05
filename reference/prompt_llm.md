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

  For `intro`, or a generated `completion` in
  [`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md):
  a template that places the generated text. It must contain `{content}`
  and can use `{id}` placeholders. For an intro, the survey puts the
  question after it, with a blank line between.

## Value

A list of class `surveychat_prompt`.

## Details

An intro gets only the answers that its placeholders name. An adaptive
question and a generated `completion` in
[`set_messages()`](https://dylanpieper.github.io/surveychat/reference/set_messages.md)
also get every answer so far, as does the LLM validation of each reply.
Each answer is one line, `- <question> (id): value`, with the question
text that the user saw.

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
