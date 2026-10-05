test_that("interpolate() fills placeholders and keeps the name of a missing one", {
  expect_equal(
    interpolate("Hi {name}, {missing}!", list(name = "Ana")),
    "Hi Ana, missing!"
  )
  expect_equal(interpolate("No placeholders", list()), "No placeholders")
  expect_null(interpolate(NULL, list()))
  expect_equal(interpolate("{x}", list(x = character(0))), "x")
  expect_equal(interpolate("{x}", list(x = c("a", "b"))), "a, b")
})

test_that("interpolate() capitalizes only at the start of a sentence", {
  data <- list(flavor = "mint", shop = "the store")

  expect_equal(
    interpolate("{shop} has {flavor}. {flavor}!", data, capitalize = TRUE),
    "The store has mint. Mint!"
  )
  expect_equal(interpolate("{shop}", data), "the store")
  expect_equal(
    interpolate("{missing} ok", data, capitalize = TRUE),
    "missing ok"
  )
})

test_that("interpolate() uses the fallback for a missing or skipped answer", {
  expect_equal(interpolate("Hey {name|there}!", list()), "Hey there!")
  expect_equal(
    interpolate("Hey {name|there}!", list(name = NA_character_)),
    "Hey there!"
  )
  expect_equal(interpolate("Hey {name|there}!", list(name = "Ana")), "Hey Ana!")
  expect_equal(
    interpolate("{name|friend}, hi.", list(), capitalize = TRUE),
    "Friend, hi."
  )
  expect_equal(interpolate("{name|}!", list()), "!")
})

test_that("extract_variables() returns names in order of use", {
  expect_equal(extract_variables("{a} and {b} and {a}"), c("a", "b", "a"))
  expect_equal(extract_variables("Hey {name|there}"), "name")
  expect_equal(extract_variables("none"), character(0))
  expect_equal(extract_variables(NULL), character(0))
})

test_that("render_message() keeps the template markdown and escapes answers", {
  html <- as.character(render_message(
    "**Thanks, {name}!** You chose {pick}.",
    list(
      name = "<img src=x onerror=alert(1)>",
      pick = "*mint* [x](javascript:y)"
    )
  ))

  expect_match(html, "<strong>Thanks, ", fixed = TRUE)
  expect_match(html, "&lt;img src=x onerror=alert(1)&gt;", fixed = TRUE)
  expect_no_match(html, "<img", fixed = TRUE)
  expect_no_match(html, "<em>", fixed = TRUE)
  expect_no_match(html, "<a ", fixed = TRUE)
  expect_match(html, "*mint* [x](javascript:y)", fixed = TRUE)
})

test_that("escape_markdown() escapes ASCII punctuation only", {
  expect_equal(escape_markdown("a*b"), "a\\*b")
  expect_equal(escape_markdown("café ’"), "café ’")
})

test_that("drop_questions() keeps only the sentences that are not questions", {
  expect_equal(
    drop_questions("You use Claude. What else would you like to explore?"),
    "You use Claude."
  )
  expect_equal(drop_questions("Ready?"), "")
  # Paragraph breaks between the kept sentences stay
  expect_equal(
    drop_questions("Great choice.\n\nWhat else?\n\nLet's continue."),
    "Great choice.\n\nLet's continue."
  )
  # An abbreviation does not end a sentence
  expect_equal(
    drop_questions("You use R, e.g. for stats. Want more?"),
    "You use R, e.g. for stats."
  )
  # The next sentence can start with a digit or a non-ASCII capital
  expect_equal(drop_questions("Which tools? 3 to go."), "3 to go.")
  expect_equal(
    drop_questions("Quel outil? \u00c9crivez-le."),
    "\u00c9crivez-le."
  )
  # Known limit: an abbreviation before a digit ends a sentence
  expect_equal(
    drop_questions("It takes approx. 3 hours? Fine."),
    "It takes approx. Fine."
  )
  # A question can end before a closing quote or bracket
  expect_equal(drop_questions('Nice. (What next?)'), "Nice.")
  expect_equal(drop_questions("Great.\n\nOn we go!"), "Great.\n\nOn we go!")
})

test_that("answers_so_far() names each answer by the question that was asked", {
  answers <- list(role = "Student", goal = "R")
  asked <- list(role = "Hey, Ana!\n\nWhat is your role?")

  expect_equal(
    answers_so_far(answers, asked),
    "Answers so far:\n- Hey, Ana! What is your role? (role): Student\n- goal: R"
  )
})
