question_of <- function(answer, choices = NULL) {
  spec <- survey_spec() |>
    add_question("q", text = "Q?", answer = answer, choices = choices)
  spec$questions[[1]]
}

test_that("form_value() keeps an enum value and refuses other values", {
  question <- question_of(ellmer::type_enum(c("Cone", "Cup"), "Serving"))

  expect_equal(
    form_value(question, "Cup"),
    list(ok = TRUE, value = "Cup", raw = "Cup", error = NULL)
  )
  bad <- form_value(question, "Bowl")
  expect_false(bad$ok)
  expect_match(bad$error, "options")
})

test_that("form_value() trims a string", {
  question <- question_of(ellmer::type_string("Name"))

  expect_equal(form_value(question, "  Ana \n")$value, "Ana")
  expect_equal(form_value(question, "  Ana \n")$raw, "Ana")
})

test_that("form_value() reads whole numbers and numbers", {
  integer <- question_of(ellmer::type_integer("Age"))
  number <- question_of(ellmer::type_number("Height"))

  expect_identical(form_value(integer, 34)$value, 34L)
  expect_identical(form_value(integer, "34")$value, 34L)
  expect_match(form_value(integer, 3.5)$error, "whole number")
  expect_match(form_value(integer, "abc")$error, "whole number")
  expect_identical(form_value(number, "1.75")$value, 1.75)
  expect_equal(form_value(number, "1.75")$raw, "1.75")
  expect_match(form_value(number, "tall")$error, "number")
})

test_that("form_value() reads yes and no as a logical", {
  question <- question_of(ellmer::type_boolean("Student"))

  expect_identical(form_value(question, "TRUE")$value, TRUE)
  expect_identical(form_value(question, FALSE)$value, FALSE)
  expect_match(form_value(question, "maybe")$error, "yes or no")
})

test_that("form_value() refuses an empty required answer", {
  question <- question_of(ellmer::type_string("Name"))

  for (empty in list(NULL, "", "   ", NA, character(0))) {
    result <- form_value(question, empty)
    expect_false(result$ok)
    expect_match(result$error, "answer this question")
  }
})

test_that("form_value() skips an empty optional answer with NA", {
  types <- list(
    ellmer::type_string("Name", required = FALSE),
    ellmer::type_integer("Age", required = FALSE),
    ellmer::type_enum(c("a", "b"), "Pick", required = FALSE)
  )
  for (type in types) {
    result <- form_value(question_of(type), "")
    expect_true(result$ok)
    expect_true(is.na(result$value))
    expect_equal(result$raw, "")
  }
})

test_that("form_reply() prefers typed text over the chosen card", {
  expect_equal(form_reply("Cone", "  a waffle  "), "a waffle")
  expect_equal(form_reply("Cone", ""), "Cone")
  expect_equal(form_reply("Cone", NULL), "Cone")
  expect_null(form_reply(NULL, " "))
})

test_that("form_input() picks an input for each answer type", {
  ns <- shiny::NS("s")
  html <- function(answer, prompt = list()) {
    question <- question_of(answer)
    prompt <- utils::modifyList(list(id = "q", text = "Q?"), prompt)
    as.character(form_input(ns, prompt, question))
  }

  enum <- html(ellmer::type_enum(c("Cone", "Cup")))
  expect_match(enum, 'type="radio" name="s-form_q" value="Cup"', fixed = TRUE)
  expect_match(html(ellmer::type_boolean()), 'value="TRUE"', fixed = TRUE)
  expect_match(html(ellmer::type_integer()), 'type="number"', fixed = TRUE)
  expect_match(html(ellmer::type_number()), 'type="number"', fixed = TRUE)
  expect_match(html(ellmer::type_string()), "<textarea", fixed = TRUE)

  with_choices <- html(
    ellmer::type_string(),
    list(generated = "Waffle", fixed = "Plain", intro = "Fun fact.")
  )
  expect_match(with_choices, 'value="Waffle"', fixed = TRUE)
  expect_match(with_choices, 'value="Plain"', fixed = TRUE)
  expect_match(with_choices, 'id="s-form_q_other"', fixed = TRUE)
  expect_match(with_choices, "Fun fact.</p>", fixed = TRUE)
  expect_match(with_choices, "Q?", fixed = TRUE)
})

test_that("form_read() combines the chosen card and the typed text", {
  question <- question_of(ellmer::type_string())
  input <- list(form_q = "Plain", form_q_other = " Waffle ")

  expect_equal(
    form_read(input, list(id = "q", fixed = "Plain"), question),
    "Waffle"
  )
  expect_equal(form_read(input, list(id = "q"), question), "Plain")
})
