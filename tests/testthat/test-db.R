for (backend in names(backends)) {
  test_that(paste("init_database() is idempotent on", backend), {
    con <- backends[[backend]]()

    expect_message(init_database(con), "Survey schema created")
    expect_silent(init_database(con))
    expect_contains(DBI::dbListTables(con), c("sessions", "responses"))
  })

  test_that(paste("row helpers write and update on", backend), {
    con <- backends[[backend]]()
    init_database(con, quiet = TRUE)

    first <- start_session(con, version = "2.0")
    second <- start_session(con)
    expect_gt(second, first)

    save_response(con, first, "name", 1, "Name?", "I'm Ana", "Ana", TRUE)
    save_response(con, first, "flavor", 2, NULL, "hmm")
    increment_retry(con, first)
    increment_retry(con, first)
    complete_session(con, first, 12)

    session <- DBI::dbGetQuery(
      con,
      "SELECT * FROM sessions ORDER BY session_id"
    )[1, ]
    expect_equal(as.logical(session$completed), TRUE)
    expect_equal(session$retry_count, 2)
    expect_equal(session$duration_seconds, 12)
    expect_equal(session$question_set_version, "2.0")

    responses <- DBI::dbGetQuery(
      con,
      "SELECT * FROM responses ORDER BY question_order"
    )
    expect_equal(responses$input_extracted, c("Ana", NA))
    expect_equal(responses$question_text, c("Name?", NA))
    expect_equal(as.logical(responses$valid), c(TRUE, NA))
  })
}

test_that("dialect_for() falls back to ANSI for an unknown driver", {
  unknown <- structure(list(), class = "UnknownConnection")
  d <- dialect_for(unknown)

  expect_equal(d$serial_pk("t", "id"), "id INTEGER PRIMARY KEY")
  expect_true(is.na(d$returning))
  expect_equal(dialect_for(local_sqlite())$returning, TRUE)
})
