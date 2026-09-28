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
