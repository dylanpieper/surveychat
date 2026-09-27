test_that("survey_server() rejects a chat or a connection of the wrong type", {
  con <- local_sqlite()

  expect_snapshot(error = TRUE, {
    survey_server("s", test_spec(), chat = list(), con = con)
    survey_server("s", test_spec(), chat = fake_chat(), con = "survey.db")
  })
})

test_that("a pool works as the connection", {
  skip_if_not_installed("pool")
  # Each pooled in-memory SQLite connection is a new database, so use a file
  path <- withr::local_tempfile(fileext = ".db")
  pool <- pool::dbPool(RSQLite::SQLite(), dbname = path)
  withr::defer(pool::poolClose(pool))

  init_database(pool, quiet = TRUE)
  first <- start_session(pool)
  second <- start_session(pool)

  expect_equal(c(first, second), c(1, 2))
  checked_out <- pool::localCheckout(pool)
  expect_equal(dialect_for(checked_out)$returning, TRUE)
})
