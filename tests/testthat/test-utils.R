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

test_that("extract_variables() returns names in order of use", {
  expect_equal(extract_variables("{a} and {b} and {a}"), c("a", "b", "a"))
  expect_equal(extract_variables("none"), character(0))
  expect_equal(extract_variables(NULL), character(0))
})
