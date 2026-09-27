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

test_that("inserts get ids without RETURNING and when a probe finds it", {
  sqlite <- dialect_for(local_sqlite())

  for (returning in list(FALSE, NA)) {
    con <- local_sqlite()
    init_database(con, quiet = TRUE)
    local_mocked_bindings(
      dialect_for = \(con) {
        utils::modifyList(sqlite, list(returning = returning))
      }
    )

    ids <- c(start_session(con), start_session(con))
    expect_equal(ids, c(1, 2))
  }
})

test_that("init_database() rejects a responses table from before 0.1.0", {
  con <- local_sqlite()
  init_database(con, quiet = TRUE)
  DBI::dbExecute(
    con,
    "ALTER TABLE responses RENAME COLUMN valid TO answered_clearly"
  )

  expect_snapshot(init_database(con), error = TRUE)
})

test_that("an unknown driver falls back when RETURNING fails", {
  con <- local_sqlite()
  init_database(con, quiet = TRUE)
  sqlite <- dialect_for(con)
  real_get_query <- DBI::dbGetQuery
  attempts <- 0
  local_mocked_bindings(
    dialect_for = \(con) utils::modifyList(sqlite, list(returning = NA))
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl(" RETURNING ", statement, fixed = TRUE)) {
        attempts <<- attempts + 1
        stop("syntax error near RETURNING")
      }
      real_get_query(conn, statement, ...)
    },
    .package = "DBI"
  )

  expect_equal(c(start_session(con), start_session(con)), c(1, 2))
  expect_equal(attempts, 2)
})
