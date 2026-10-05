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

test_that("form_input() picks an input for each answer type", {
  ns <- shiny::NS("s")
  html <- function(answer, prompt = list()) {
    question <- question_of(answer)
    prompt <- utils::modifyList(list(id = "q", text = "Q?"), prompt)
    as.character(form_input(ns, prompt, question))
  }

  enum <- html(ellmer::type_enum(c("Cone", "Cup")))
  expect_match(enum, 'data-pick="s-form_pick_q" data-value="Cup"', fixed = TRUE)
  expect_match(html(ellmer::type_boolean()), 'value="TRUE"', fixed = TRUE)
  expect_match(html(ellmer::type_integer()), 'type="number"', fixed = TRUE)
  expect_match(html(ellmer::type_number()), 'type="number"', fixed = TRUE)
  expect_match(html(ellmer::type_string()), "<textarea", fixed = TRUE)

  with_choices <- html(
    ellmer::type_string(),
    list(generated = "Waffle", fixed = "Plain", intro = "Fun fact.")
  )
  for (choice in c("Waffle", "Plain")) {
    expect_match(
      with_choices,
      sprintf('data-pick="s-form_pick_q" data-value="%s"', choice),
      fixed = TRUE
    )
  }
  expect_match(with_choices, 'id="s-form_q" type="text"', fixed = TRUE)
  expect_match(with_choices, "Or type your own", fixed = TRUE)
  expect_no_match(with_choices, 'type="radio"', fixed = TRUE)
  expect_match(with_choices, "Fun fact.</p>", fixed = TRUE)
  expect_match(with_choices, "Q?", fixed = TRUE)
})

test_that("form_read() reads the input of the prompt", {
  input <- list(form_q = " Waffle ", form_r = "x")

  expect_equal(form_read(input, list(id = "q")), " Waffle ")
})

test_that("form_value() refuses numbers outside the range of the type", {
  integer <- question_of(ellmer::type_integer("Age"))
  number <- question_of(ellmer::type_number("Height"))

  expect_match(form_value(integer, 1e10)$error, "whole number")
  expect_match(form_value(integer, "Inf")$error, "whole number")
  expect_match(form_value(number, "Inf")$error, "number")
  expect_match(form_value(number, NaN)$error, "answer this question")
})

test_that("form_text() writes numbers without scientific notation", {
  expect_equal(form_text(100000), "100000")
  expect_equal(form_text(1.75), "1.75")
  expect_equal(
    form_value(question_of(ellmer::type_integer()), 100000)$raw,
    "100000"
  )
})

test_that("form_echo() shows the label of a yes or no choice", {
  boolean <- question_of(ellmer::type_boolean())
  string <- question_of(ellmer::type_string())

  expect_equal(form_echo(boolean, "TRUE", "(skipped)"), "Yes")
  expect_equal(form_echo(boolean, "FALSE", "(skipped)"), "No")
  expect_equal(form_echo(string, "Ana", "(skipped)"), "Ana")
  expect_equal(form_echo(string, "", "(none)"), "(none)")
})

test_that("form_value() keeps every item of a multi-select answer", {
  question <- question_of(
    ellmer::type_array(ellmer::type_enum(c("Vegan", "No nuts", "Halal")))
  )

  expect_equal(
    form_value(question, c("Vegan", "No nuts")),
    list(
      ok = TRUE,
      value = c("Vegan", "No nuts"),
      raw = '["Vegan","No nuts"]',
      error = NULL
    )
  )
  expect_match(form_value(question, c("Vegan", "Kosher"))$error, "options")
  expect_match(form_value(question, NULL)$error, "at least one")

  optional <- ellmer::type_array(
    ellmer::type_enum(c("Vegan", "Halal")),
    required = FALSE
  )
  expect_equal(form_value(question_of(optional), NULL)$value, NA)
  expect_false(form_needs_validation(question, list(), '["Vegan"]'))
})

test_that("form_value() keeps a date as ISO text", {
  spec <- survey_spec() |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date")
  question <- spec$questions[[1]]

  expect_equal(form_value(question, as.Date("2026-11-03"))$value, "2026-11-03")
  expect_equal(form_value(question, "2026-11-03")$raw, "2026-11-03")
  expect_match(form_value(question, "next week")$error, "date")
  # The input checks the date, so it needs no LLM call
  expect_false(form_needs_validation(question, list(), "2026-11-03"))
})

test_that("form_input() shows checkboxes and a date input", {
  ns <- shiny::NS("s")
  multi <- list(
    answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))
  )
  date <- list(answer = ellmer::type_string(), input = "date")
  prompt <- list(id = "a", text = "A?")

  checkboxes <- as.character(form_input(ns, prompt, multi))
  expect_match(checkboxes, "shiny-input-checkboxgroup", fixed = TRUE)
  expect_match(checkboxes, 'value="Halal"', fixed = TRUE)

  expect_match(
    as.character(form_input(ns, prompt, date)),
    'data-initial-date=""',
    fixed = TRUE
  )
})

test_that("form_echo() lists every item of a multi-select answer", {
  multi <- list(
    answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))
  )

  expect_equal(form_echo(multi, c("Vegan", "Halal"), "(none)"), "Vegan, Halal")
  expect_equal(form_echo(multi, NULL, "(none)"), "(none)")
})
