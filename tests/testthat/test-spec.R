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
  expect_named(question$schema@properties, c("name", "valid"))
  expect_equal(question$valid, default_config()$valid)
})

test_that("the valid condition becomes a TRUE/FALSE instruction", {
  schema <- answer_schema("flavor", ellmer::type_string(), "they named one.")

  expect_equal(
    schema@properties$valid@description,
    "TRUE if the reply is valid: they named one. Otherwise FALSE."
  )
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
  expect_named(schema@properties, c("name", "valid", "flavor"))
  flavor <- schema@properties$flavor
  expect_false(flavor@required)
  # The current question's placeholder is named plainly, not as a bare id
  expect_match(
    flavor@description,
    "\"(the answer to this question), flavor?\"",
    fixed = TRUE
  )
  expect_match(flavor@description, "Flavor", fixed = TRUE)
  expect_match(flavor@description, spec$config$valid, fixed = TRUE)
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
    "\"How old are you?\" and the age is 18 or older. ",
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
