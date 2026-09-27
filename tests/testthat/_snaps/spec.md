# add_question() rejects bad input

    Code
      add_question(list(), "a", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! `spec` must be a survey spec, not an empty list.
      i Start the pipe with `survey_spec()`.
    Code
      add_question(spec, "name", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! The spec already has a question with id "name".
    Code
      add_question(spec, "my id", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! `id` must be a syntactic name, not "my id".
    Code
      add_question(spec, "content", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! `id` cannot be "content"; the package uses that name.
    Code
      add_question(spec, "a", text = 1, answer = answer)
    Condition
      Error in `add_question()`:
      ! `text` must be made with `prompt_llm()`, not a number.
    Code
      add_question(spec, "a", text = "A?", answer = "string")
    Condition
      Error in `add_question()`:
      ! `answer` must be an ellmer type such as `ellmer::type_string()`, not a string.
    Code
      add_question(spec, "a", text = "A?", answer = answer, intro = prompt_llm("x"))
    Condition
      Error in `add_question()`:
      ! `intro` needs a `format` that places `{content}`.

# add_question() warns about placeholders that name no earlier question

    Code
      add_question(spec, "flavor", text = "{nme}, flavor? {flavor}", answer = ellmer::type_string())
    Condition
      Warning:
      Question flavor uses placeholders `{nme}` and `{flavor}` that do not name an earlier question.
      i The user will see the raw name. Check the spelling and the order of the questions.
    Output
      <surveychat_spec> version "1.0", 2 questions
      1. name
      2. flavor

# prompt_llm() checks its format

    Code
      prompt_llm(c("a", "b"))
    Condition
      Error in `prompt_llm()`:
      ! `prompt` must be a single string, not a character vector.
    Code
      prompt_llm("Hi", format = "No placeholder")
    Condition
      Error in `prompt_llm()`:
      ! `format` must contain `{content}`.

# set_messages() and set_config() reject bad values

    Code
      set_messages(survey_spec(), welcome = 1)
    Condition
      Error in `set_messages()`:
      ! `welcome` must be a single string, not a number.
    Code
      set_config(survey_spec(), tries = 1.5)
    Condition
      Error in `set_config()`:
      ! `tries` must be a non-negative whole number, not 1.5.
    Code
      set_config(survey_spec(), character_delay = -1)
    Condition
      Error in `set_config()`:
      ! `character_delay` must be a non-negative number, not -1.

# validate_spec() needs a question and a fixed first question

    Code
      validate_spec(survey_spec())
    Condition
      Error:
      ! The survey has no questions.
      i Add one with `add_question()`.
    Code
      validate_spec(adaptive_first)
    Condition
      Error:
      ! The first question "a" cannot be adaptive.
      i There are no earlier answers for its prompt to use.

---

    Code
      validate_spec(set_messages(test_spec(), completion = "Bye {nam}"))
    Condition
      Warning:
      The completion message uses placeholder `{nam}` that does not name an earlier question.
      i The user will see the raw name. Check the spelling and the order of the questions.

# print() lists each question with its tags

    Code
      print(test_spec())
    Output
      <surveychat_spec> version "1.0", 3 questions
      1. name
      2. flavor [intro]
      3. why [adaptive]

