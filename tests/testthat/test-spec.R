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
    add_question(spec, "a", text = 1, answer = answer)
    add_question(spec, "a", text = "A?", answer = "string")
    add_question(
      spec,
      "a",
      text = "A?",
      answer = answer,
      intro = prompt_llm("x")
    )
  })
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
  expect_equal(changed$messages[-1], spec$messages[-1])
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
})
