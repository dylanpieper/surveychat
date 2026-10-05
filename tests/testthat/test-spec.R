test_that("the pipe builds a plain list with questions, messages, and config", {
  spec <- test_spec()

  expect_s3_class(spec, "surveychat_spec")
  expect_named(spec, c("questions", "messages", "config"))
  expect_equal(
    vapply(spec$questions, \(q) q$id, ""),
    c("name", "flavor", "why")
  )
  expect_equal(spec$messages$completion, "Bye {name}")
  expect_equal(spec$config$tries, 1)
})

test_that("add_question() builds a schema with the answer and the valid flag", {
  question <- test_spec()$questions[[1]]

  expect_s7_class(question$schema, ellmer::TypeObject)
  expect_named(question$schema@properties, c("name", "valid", "retry_hint"))
  expect_equal(question$valid, default_config()$valid)
})

test_that("the valid condition becomes a TRUE/FALSE instruction", {
  schema <- answer_schema("flavor", ellmer::type_string(), "they named one.")

  expect_equal(
    schema@properties$valid@description,
    "TRUE if the reply is valid: they named one. Otherwise FALSE."
  )
})

test_that("only a default rule adds the strict and lenient clauses", {
  rule <- function(answer, valid = NULL) {
    spec <- survey_spec() |>
      add_question("q", text = "Q?", answer = answer, valid = valid)
    spec$questions[[1]]$schema@properties$valid@description
  }
  yes_no <- ellmer::type_boolean("Yes or no")

  expect_match(rule(yes_no), "not a clear yes or no", fixed = TRUE)
  expect_no_match(rule(yes_no), "When in doubt", fixed = TRUE)
  expect_match(rule(ellmer::type_string("Text")), "When in doubt", fixed = TRUE)
  expect_no_match(
    rule(ellmer::type_enum(c("A", "B"), "Pick")),
    "When in doubt",
    fixed = TRUE
  )
  # A date input is not free text
  date <- survey_spec() |>
    add_question(
      "d",
      text = "D?",
      answer = ellmer::type_string("Date"),
      input = "date"
    )
  expect_no_match(
    date$questions[[1]]$schema@properties$valid@description,
    "When in doubt",
    fixed = TRUE
  )
  # An own rule is kept as written, also when it matches the default text
  own <- rule(yes_no, valid = default_config()$valid)
  expect_no_match(own, "not a clear yes or no", fixed = TRUE)
  expect_no_match(own, "When in doubt", fixed = TRUE)
})

test_that("valid uses the default at the time of the call", {
  spec <- survey_spec() |>
    add_question("a", text = "A?", answer = ellmer::type_string()) |>
    set_config(valid = "New rule") |>
    add_question("b", text = "B?", answer = ellmer::type_string()) |>
    add_question(
      "c",
      text = "C?",
      answer = ellmer::type_string(),
      valid = "Own"
    )

  valids <- vapply(spec$questions, \(q) q$valid, "")
  expect_equal(valids, c(default_config()$valid, "New rule", "Own"))
  expect_equal(
    vapply(spec$questions, \(q) q$own_valid, TRUE),
    c(FALSE, FALSE, TRUE)
  )
})

test_that("add_question() rejects bad input", {
  spec <- test_spec()
  answer <- ellmer::type_string()

  expect_snapshot(error = TRUE, {
    add_question(list(), "a", text = "A?", answer = answer)
    add_question(spec, "name", text = "A?", answer = answer)
    add_question(spec, "my id", text = "A?", answer = answer)
    add_question(spec, "content", text = "A?", answer = answer)
    add_question(spec, ".description", text = "A?", answer = answer)
    add_question(spec, "a", text = 1, answer = answer)
    add_question(spec, "a", text = "A?", answer = "string")
    add_question(
      spec,
      "a",
      text = "A?",
      answer = ellmer::type_array(ellmer::type_string())
    )
    add_question(
      spec,
      "a",
      text = "A?",
      answer = answer,
      intro = prompt_llm("x")
    )
  })
})

test_that("add_question() keeps enum values, preset, or generated choices", {
  spec <- survey_spec()
  enum <- ellmer::type_enum(c("cone", "cup"))
  string <- ellmer::type_string()
  choices_of <- function(...) {
    add_question(spec, "a", text = "A?", ...)$questions[[1]]$choices
  }

  ideas <- prompt_llm("Ideas")

  expect_null(choices_of(answer = string))
  expect_equal(
    choices_of(answer = enum),
    list(prompt = NULL, fixed = c("cone", "cup"))
  )
  expect_equal(
    choices_of(answer = enum, choices = "cone"),
    list(prompt = NULL, fixed = "cone")
  )
  expect_equal(
    choices_of(answer = string, choices = c("x", "y")),
    list(prompt = NULL, fixed = c("x", "y"))
  )
  expect_equal(
    choices_of(answer = string, choices = ideas),
    list(prompt = ideas, fixed = NULL)
  )
  expect_equal(
    choices_of(answer = string, choices = list(ideas, "None", c("x", "y"))),
    list(prompt = ideas, fixed = c("None", "x", "y"))
  )
})

test_that("extraction_schema() adds optional early fields with their question", {
  spec <- test_spec()
  first <- spec$questions[[1]]

  expect_identical(extraction_schema(first, list(), list()), first$schema)

  schema <- extraction_schema(first, spec$questions[2], list())
  expect_named(schema@properties, c("name", "valid", "retry_hint", "flavor"))
  flavor <- schema@properties$flavor
  expect_false(flavor@required)
  # The current question's placeholder is named plainly, not as a bare id
  expect_match(
    flavor@description,
    "\"(the answer to this question), flavor?\"",
    fixed = TRUE
  )
  expect_match(flavor@description, "Flavor", fixed = TRUE)
  # The default rule is not added; it could read as the current question's
  expect_no_match(flavor@description, spec$config$valid, fixed = TRUE)
  # The spec keeps its own answer types
  expect_true(spec$questions[[2]]$answer@required)
})

test_that("an early field carries the later question's own valid rule", {
  spec <- survey_spec() |>
    add_question("name", text = "Name?", answer = ellmer::type_string()) |>
    add_question(
      "age",
      text = "How old are you?",
      answer = ellmer::type_integer(),
      valid = "the age is 18 or older."
    )

  schema <- extraction_schema(spec$questions[[1]], spec$questions[2], list())
  expect_match(
    schema@properties$age@description,
    "\"How old are you?\", and for that question the age is 18 or older. ",
    fixed = TRUE
  )
})

test_that("add_question() rejects bad choices", {
  spec <- survey_spec()
  answer <- ellmer::type_string()

  expect_snapshot(error = TRUE, {
    add_question(spec, "a", text = "A?", answer = answer, choices = 1:3)
    add_question(spec, "a", text = "A?", answer = answer, choices = c("x", ""))
    add_question(spec, "a", text = "A?", answer = answer, choices = character())
    add_question(
      spec,
      "a",
      text = "A?",
      answer = answer,
      choices = list(prompt_llm("x"), prompt_llm("y"))
    )
    add_question(spec, "a", text = "A?", answer = answer, choices = list(1))
    add_question(
      spec,
      "a",
      text = "A?",
      answer = ellmer::type_enum(c("cone", "cup")),
      choices = c("cone", "large")
    )
    add_question(
      spec,
      "a",
      text = "A?",
      answer = answer,
      choices = prompt_llm("x", format = "{content}")
    )
  })
})

test_that("add_question() warns about placeholders in the choices prompt", {
  spec <- survey_spec() |>
    add_question("name", text = "Name?", answer = ellmer::type_string())

  expect_snapshot(
    add_question(
      spec,
      "flavor",
      text = "Flavor?",
      answer = ellmer::type_string(),
      choices = prompt_llm("Ideas for {nme}")
    )
  )
})

test_that("add_question() warns about placeholders that name no earlier question", {
  spec <- survey_spec() |>
    add_question("name", text = "Name?", answer = ellmer::type_string())

  expect_snapshot(
    add_question(
      spec,
      "flavor",
      text = "{nme}, flavor? {flavor}",
      answer = ellmer::type_string()
    )
  )
  expect_no_warning(
    add_question(
      spec,
      "flavor",
      text = "{name}?",
      intro = prompt_llm("Fact", format = "{content}"),
      answer = ellmer::type_string()
    )
  )
})

test_that("prompt_llm() checks its format", {
  expect_s3_class(prompt_llm("Hi"), "surveychat_prompt")
  expect_snapshot(error = TRUE, {
    prompt_llm(c("a", "b"))
    prompt_llm("Hi", format = "No placeholder")
  })
})

test_that("set_messages() and set_config() change only the named fields", {
  spec <- survey_spec()
  changed <- spec |>
    set_messages(welcome = "Hey") |>
    set_config(tries = 5)

  expect_equal(changed$messages$welcome, "Hey")
  expect_equal(
    changed$messages[names(changed$messages) != "welcome"],
    spec$messages[names(spec$messages) != "welcome"]
  )
  expect_equal(changed$config$tries, 5)
  expect_equal(
    changed$config[names(changed$config) != "tries"],
    spec$config[names(spec$config) != "tries"]
  )
})

test_that("set_config() turns the model check on by default and off on request", {
  expect_true(survey_spec()$config$check_model)
  expect_false(
    set_config(survey_spec(), check_model = FALSE)$config$check_model
  )
  expect_error(set_config(survey_spec(), check_model = "no"), "check_model")
})

test_that("set_config() sets the views, with the chat by default", {
  expect_equal(survey_spec()$config$views, "chat")
  expect_equal(
    set_config(survey_spec(), views = c("chat", "form"))$config$views,
    c("chat", "form")
  )
  expect_equal(
    set_config(survey_spec(), views = "side_by_side")$config$views,
    "side_by_side"
  )
})

test_that("set_config() rejects bad views", {
  expect_error(set_config(survey_spec(), views = "web"), "views")
  expect_error(set_config(survey_spec(), views = c("chat", "chat")), "once")
  expect_error(set_config(survey_spec(), views = character()), "views")
  expect_error(set_config(survey_spec(), views = 1), "views")
  expect_error(set_config(survey_spec(), views = NA_character_), "views")
})

test_that("view_methods() gives the answer methods of the views in order", {
  expect_equal(view_methods("chat"), "chat")
  expect_equal(view_methods(c("chat", "form")), c("chat", "form"))
  expect_equal(view_methods("side_by_side"), c("form", "chat"))
  expect_equal(view_methods(c("chat", "side_by_side")), c("chat", "form"))
})

test_that("print() shows the views when there is more than the chat", {
  expect_output(print(test_spec()), "^[^\n]*questions\n")
  expect_output(
    print(set_config(test_spec(), views = c("form", "chat"))),
    "views form, chat"
  )
})

test_that("set_messages() and set_config() reject bad values", {
  expect_snapshot(error = TRUE, {
    set_messages(survey_spec(), welcome = 1)
    set_config(survey_spec(), tries = 1.5)
    set_config(survey_spec(), character_delay = -1)
    set_config(survey_spec(), skip_answered = "yes")
  })
})

test_that("validate_spec() needs a question and a fixed first question", {
  adaptive_first <- survey_spec() |>
    add_question("a", text = prompt_llm("Ask"), answer = ellmer::type_string())

  expect_snapshot(error = TRUE, {
    validate_spec(survey_spec())
    validate_spec(adaptive_first)
  })
  expect_snapshot(
    validate_spec(test_spec() |> set_messages(completion = "Bye {nam}"))
  )
})

test_that("print() lists each question with its tags", {
  expect_snapshot(print(test_spec()))
  expect_snapshot(print(
    test_spec() |>
      add_question(
        "serve",
        text = "Serve?",
        answer = ellmer::type_enum(c("cone", "cup"))
      ) |>
      add_question(
        "topping",
        text = "Topping?",
        answer = ellmer::type_string(),
        choices = prompt_llm("Toppings for {flavor}")
      )
  ))
})

test_that("add_question() reserves the retry_hint id", {
  expect_error(
    add_question(survey_spec(), "retry_hint", "Q?", ellmer::type_string()),
    "package uses that name"
  )
})

test_that("add_question() keeps a `when` rule on earlier answers", {
  spec <- test_spec() |>
    add_question(
      "topping",
      text = "Topping?",
      answer = ellmer::type_string(),
      when = ~ flavor == "mint"
    )

  expect_equal(spec$questions[[4]]$when, ~ flavor == "mint", ignore_attr = TRUE)
  expect_null(spec$questions[[1]]$when)
})

test_that("add_question() rejects a bad `when` rule", {
  spec <- test_spec()
  answer <- ellmer::type_string()

  expect_snapshot(error = TRUE, {
    add_question(spec, "a", text = "A?", answer = answer, when = "name")
    add_question(spec, "a", text = "A?", answer = answer, when = x ~ name)
    add_question(spec, "a", text = "A?", answer = answer, when = ~ nam == 1)
    add_question(spec, "a", text = "A?", answer = answer, when = ~ a == 1)
  })
})

test_that("validate_spec() rejects a `when` rule on the first question", {
  spec <- survey_spec() |>
    add_question("a", text = "A?", answer = ellmer::type_string(), when = ~TRUE)

  expect_snapshot(validate_spec(spec), error = TRUE)
})

test_that("print() tags a question with a `when` rule", {
  spec <- test_spec() |>
    add_question(
      "topping",
      text = "Topping?",
      answer = ellmer::type_string(),
      when = ~ flavor == "mint"
    )

  expect_snapshot(print(spec))
})

test_that("a `when` rule can use names from its environment", {
  min_age <- 18
  spec <- survey_spec() |>
    add_question("age", text = "Age?", answer = ellmer::type_integer()) |>
    add_question(
      "drink",
      text = "Drink?",
      answer = ellmer::type_string(),
      when = ~ age >= min_age & T
    )

  expect_true(when_applies(spec$questions[[2]], list(age = 30L)))
  expect_false(when_applies(spec$questions[[2]], list(age = 12L)))
})

test_that("add_question() takes a multi-select answer and shows its values", {
  spec <- survey_spec() |>
    add_question(
      "diet",
      text = "Diet?",
      answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "No nuts")))
    )

  # The chat shows checkboxes, so there are no cards
  expect_null(spec$questions[[1]]$choices)
  expect_equal(question_kind(spec$questions[[1]]), "multi")
})

test_that("add_question() takes a date input for a string answer", {
  spec <- survey_spec() |>
    add_question(
      "day",
      text = "Which day?",
      answer = ellmer::type_string("The day"),
      input = "date"
    )
  question <- spec$questions[[1]]

  expect_equal(question$input, "date")
  expect_equal(question_kind(question), "date")
  expect_match(question$answer@description, "YYYY-MM-DD", fixed = TRUE)
})

test_that("add_question() rejects a bad input hint", {
  expect_snapshot(error = TRUE, {
    add_question(
      survey_spec(),
      "a",
      text = "A?",
      answer = ellmer::type_string(),
      input = "email"
    )
    add_question(
      survey_spec(),
      "a",
      text = "A?",
      answer = ellmer::type_integer(),
      input = "date"
    )
  })
})

test_that("add_question() checks choices for a multi-select or a date", {
  multi <- ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))

  expect_snapshot(error = TRUE, {
    add_question(survey_spec(), "a", "A?", multi, choices = "Kosher")
    add_question(survey_spec(), "a", "A?", multi, choices = prompt_llm("x"))
    add_question(
      survey_spec(),
      "a",
      "A?",
      ellmer::type_string(),
      input = "date",
      choices = "Today"
    )
  })
})

test_that("extraction_schema() tells a date question today's date", {
  local_mocked_bindings(now = function() as.POSIXct("2026-10-03 12:00:00"))
  spec <- survey_spec() |>
    add_question("name", text = "Name?", answer = ellmer::type_string()) |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date")

  current <- extraction_schema(spec$questions[[2]], list(), list())
  early <- extraction_schema(spec$questions[[1]], spec$questions[2], list())

  expect_match(current@properties$day@description, "Today is 2026-10-03.")
  expect_match(early@properties$day@description, "Today is 2026-10-03.")
})

test_that("a date description ends with a period before the format", {
  description_of <- function(answer) {
    spec <- add_question(survey_spec(), "d", "D?", answer, input = "date")
    spec$questions[[1]]$answer@description
  }
  format <- "Use the ISO date format YYYY-MM-DD."

  expect_equal(
    description_of(ellmer::type_string("Day")),
    paste("Day.", format)
  )
  expect_equal(
    description_of(ellmer::type_string("Day.")),
    paste("Day.", format)
  )
  expect_equal(description_of(ellmer::type_string()), format)
})

test_that("set_messages() takes a generated completion with a format", {
  spec <- test_spec() |>
    set_messages(
      completion = prompt_llm(
        "Reflect on {flavor}.",
        format = "{content}\n\nBye {name}"
      )
    )

  expect_s3_class(spec$messages$completion, "surveychat_prompt")
  expect_snapshot(error = TRUE, {
    set_messages(survey_spec(), completion = prompt_llm("No format"))
  })
  expect_snapshot(validate_spec(
    test_spec() |>
      set_messages(completion = prompt_llm("{nam}", format = "{content}"))
  ))
})

test_that("the default rule of a yes or no question treats a vague reply as not valid", {
  spec <- survey_spec() |>
    add_question("dinner", "Dinner?", ellmer::type_boolean("Dinner")) |>
    add_question(
      "club",
      "Club?",
      ellmer::type_boolean("Club"),
      valid = "any reply, including not sure"
    ) |>
    add_question("flavor", "Flavor?", ellmer::type_string("Flavor"))
  rule_of <- function(question) question$schema@properties$valid@description

  expect_match(rule_of(spec$questions[[1]]), "maybe", fixed = TRUE)
  # An own rule and other answer types keep their rule as written
  expect_no_match(rule_of(spec$questions[[2]]), "maybe", fixed = TRUE)
  expect_no_match(rule_of(spec$questions[[3]]), "maybe", fixed = TRUE)
})

test_that("a custom default rule keeps its wording on a yes or no question", {
  spec <- survey_spec() |>
    set_config(valid = "any reply, even not sure") |>
    add_question("dinner", "Dinner?", ellmer::type_boolean("Dinner"))

  expect_no_match(
    spec$questions[[1]]$schema@properties$valid@description,
    "maybe",
    fixed = TRUE
  )
})

test_that("the default rule treats examples in the question as suggestions", {
  spec <- survey_spec() |>
    add_question("kind", "Kind?", ellmer::type_string("Kind")) |>
    add_question("own", "Own?", ellmer::type_string("Own"), valid = "a color")
  rule_of <- function(question) question$schema@properties$valid@description
  hint_of <- function(question) {
    question$schema@properties$retry_hint@description
  }

  expect_match(rule_of(spec$questions[[1]]), "only suggestions", fixed = TRUE)
  expect_no_match(
    rule_of(spec$questions[[2]]),
    "only suggestions",
    fixed = TRUE
  )
  expect_match(
    hint_of(spec$questions[[1]]),
    "Do not repeat the question",
    fixed = TRUE
  )
})
