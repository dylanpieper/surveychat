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
      ! `id` must be a syntactic name that does not start with a dot, not "my id".
    Code
      add_question(spec, "content", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! `id` cannot be "content"; the package uses that name.
    Code
      add_question(spec, ".description", text = "A?", answer = answer)
    Condition
      Error in `add_question()`:
      ! `id` must be a syntactic name that does not start with a dot, not ".description".
    Code
      add_question(spec, "a", text = 1, answer = answer)
    Condition
      Error in `add_question()`:
      ! `text` must be made with `prompt_llm()`, not a number.
    Code
      add_question(spec, "a", text = "A?", answer = "string")
    Condition
      Error in `add_question()`:
      ! `answer` must be a scalar ellmer type or a multi-select, not a string.
      i Use `ellmer::type_string()`, `ellmer::type_number()`, `ellmer::type_integer()`, `ellmer::type_boolean()`, `ellmer::type_enum()`, or `ellmer::type_array(ellmer::type_enum(...))`.
    Code
      add_question(spec, "a", text = "A?", answer = ellmer::type_array(ellmer::type_string()))
    Condition
      Error in `add_question()`:
      ! `answer` must be a scalar ellmer type or a multi-select, not an <ellmer::TypeArray> object.
      i Use `ellmer::type_string()`, `ellmer::type_number()`, `ellmer::type_integer()`, `ellmer::type_boolean()`, `ellmer::type_enum()`, or `ellmer::type_array(ellmer::type_enum(...))`.
    Code
      add_question(spec, "a", text = "A?", answer = answer, intro = prompt_llm("x"))
    Condition
      Error in `add_question()`:
      ! `intro` needs a `format` that places `{content}`.

# add_question() rejects bad choices

    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = 1:3)
    Condition
      Error in `add_question()`:
      ! `choices` must be `NULL`, a character vector with no empty values, a `prompt_llm()`, or a list of one `prompt_llm()` and strings.
      x It is an integer vector.
    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = c("x", ""))
    Condition
      Error in `add_question()`:
      ! `choices` must be `NULL`, a character vector with no empty values, a `prompt_llm()`, or a list of one `prompt_llm()` and strings.
      x It is a character vector.
    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = character())
    Condition
      Error in `add_question()`:
      ! `choices` must be `NULL`, a character vector with no empty values, a `prompt_llm()`, or a list of one `prompt_llm()` and strings.
      x It is an empty character vector.
    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = list(prompt_llm(
        "x"), prompt_llm("y")))
    Condition
      Error in `add_question()`:
      ! `choices` must be `NULL`, a character vector with no empty values, a `prompt_llm()`, or a list of one `prompt_llm()` and strings.
      x It is a list.
    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = list(1))
    Condition
      Error in `add_question()`:
      ! `choices` must be `NULL`, a character vector with no empty values, a `prompt_llm()`, or a list of one `prompt_llm()` and strings.
      x It is a list.
    Code
      add_question(spec, "a", text = "A?", answer = ellmer::type_enum(c("cone", "cup")),
      choices = c("cone", "large"))
    Condition
      Error in `add_question()`:
      ! Each choice of an enum answer must be one of its values.
      x "large" is not in "cone" and "cup".
    Code
      add_question(spec, "a", text = "A?", answer = answer, choices = prompt_llm("x",
        format = "{content}"))
    Condition
      Error in `add_question()`:
      ! `choices` cannot have a `format`.

# add_question() warns about placeholders in the choices prompt

    Code
      add_question(spec, "flavor", text = "Flavor?", answer = ellmer::type_string(),
      choices = prompt_llm("Ideas for {nme}"))
    Condition
      Warning:
      Question flavor uses placeholder `{nme}` that does not name an earlier question.
      i The user will see the raw name. Check the spelling and the order of the questions.
    Output
      <surveychat_spec> version "1.0", 2 questions
      1. name
      2. flavor [generated choices]

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
    Code
      set_config(survey_spec(), skip_answered = "yes")
    Condition
      Error in `set_config()`:
      ! `skip_answered` must be `TRUE` or `FALSE`, not a string.

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

---

    Code
      print(add_question(add_question(test_spec(), "serve", text = "Serve?", answer = ellmer::type_enum(
        c("cone", "cup"))), "topping", text = "Topping?", answer = ellmer::type_string(),
      choices = prompt_llm("Toppings for {flavor}")))
    Output
      <surveychat_spec> version "1.0", 5 questions
      1. name
      2. flavor [intro]
      3. why [adaptive]
      4. serve [choices]
      5. topping [generated choices]

# add_question() rejects a bad `when` rule

    Code
      add_question(spec, "a", text = "A?", answer = answer, when = "name")
    Condition
      Error in `add_question()`:
      ! `when` must be a one-sided formula, such as `~ served == "Cone"`.
    Code
      add_question(spec, "a", text = "A?", answer = answer, when = x ~ name)
    Condition
      Error in `add_question()`:
      ! `when` must be a one-sided formula, such as `~ served == "Cone"`.
    Code
      add_question(spec, "a", text = "A?", answer = answer, when = ~ nam == 1)
    Condition
      Error in `add_question()`:
      ! `when` uses name "nam" that does not name an earlier question.
      i A rule can use only the answers to earlier questions.
    Code
      add_question(spec, "a", text = "A?", answer = answer, when = ~ a == 1)
    Condition
      Error in `add_question()`:
      ! `when` uses name "a" that does not name an earlier question.
      i A rule can use only the answers to earlier questions.

# validate_spec() rejects a `when` rule on the first question

    Code
      validate_spec(spec)
    Condition
      Error:
      ! The first question "a" cannot have a `when` rule.
      i There are no earlier answers for the rule to use.

# print() tags a question with a `when` rule

    Code
      print(spec)
    Output
      <surveychat_spec> version "1.0", 4 questions
      1. name
      2. flavor [intro]
      3. why [adaptive]
      4. topping [when]

# add_question() rejects a bad input hint

    Code
      add_question(survey_spec(), "a", text = "A?", answer = ellmer::type_string(),
      input = "email")
    Condition
      Error in `add_question()`:
      ! `input` must be `NULL` or "date", not "email".
    Code
      add_question(survey_spec(), "a", text = "A?", answer = ellmer::type_integer(),
      input = "date")
    Condition
      Error in `add_question()`:
      ! `input = "date"` needs an answer from `ellmer::type_string()`.

# add_question() checks choices for a multi-select or a date

    Code
      add_question(survey_spec(), "a", "A?", multi, choices = "Kosher")
    Condition
      Error in `add_question()`:
      ! Each choice of an enum answer must be one of its values.
      x "Kosher" is not in "Vegan" and "Halal".
    Code
      add_question(survey_spec(), "a", "A?", multi, choices = prompt_llm("x"))
    Condition
      Error in `add_question()`:
      ! A multi-select answer cannot have generated `choices`.
    Code
      add_question(survey_spec(), "a", "A?", ellmer::type_string(), input = "date",
      choices = "Today")
    Condition
      Error in `add_question()`:
      ! A date input cannot have `choices`.

# set_messages() takes a generated completion with a format

    Code
      set_messages(survey_spec(), completion = prompt_llm("No format"))
    Condition
      Error in `set_messages()`:
      ! A generated `completion` needs a `format` that places `{content}`.

---

    Code
      validate_spec(set_messages(test_spec(), completion = prompt_llm("{nam}",
        format = "{content}")))
    Condition
      Warning:
      The completion prompt uses placeholder `{nam}` that does not name an earlier question.
      i The user will see the raw name. Check the spelling and the order of the questions.

