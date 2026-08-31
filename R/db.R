#' Database setup and operations
#'
#' Every statement here is built from DBI primitives and the dialect table, so
#' the same code runs against any driver. Three rules keep it portable:
#'
#' - Identifiers and values pass through `dbQuoteIdentifier()` and
#'   `dbQuoteLiteral()`, never through `?` or `$1` placeholders, whose syntax
#'   differs by driver.
#' - The schema is built from `dialect_for()` fragments instead of literal DDL.
#' - Dates and durations are computed in R, never with SQL date functions.

box::use(
  DBI[dbExecute, dbExistsTable, dbGetQuery, dbQuoteIdentifier, dbQuoteLiteral,
      dbWithTransaction, SQL],
  cli[cli_alert_success],
  R/dialect[dialect_for, on_connect],
)

#' Quote a named list of values as a `(columns) VALUES (values)` pair
#' @noRd
quoted_row <- \(con, values) {
  # NULL and the zero-length results of as.character(NULL) both mean SQL NULL
  values <- lapply(values, \(value) if (length(value) == 0) NA else value)
  list(
    columns = SQL(paste(
      dbQuoteIdentifier(con, names(values)),
      collapse = ", "
    )),
    values = SQL(paste(
      vapply(values, \(value) as.character(dbQuoteLiteral(con, value)), ""),
      collapse = ", "
    ))
  )
}

#' Insert one row and return its generated primary key
#'
#' Uses `INSERT ... RETURNING` where the driver has it. Otherwise the insert and
#' the id lookup share a transaction, so a concurrent writer cannot slip between
#' them. A driver with no dialect entry tries `RETURNING` and drops to the
#' transaction if the driver rejects it.
#' @noRd
insert_returning_id <- \(con, table, values, id_column) {
  d <- dialect_for(con)
  row <- quoted_row(con, values)
  target <- dbQuoteIdentifier(con, table)
  id <- dbQuoteIdentifier(con, id_column)
  insert <- paste0("INSERT INTO ", target, " (", row$columns, ") VALUES (", row$values, ")")

  returning <- \() dbGetQuery(con, paste0(insert, " RETURNING ", id, " AS id"))$id

  two_step <- \() {
    dbWithTransaction(con, {
      dbExecute(con, insert)
      dbGetQuery(con, d$last_id(table, id_column))$id
    })
  }

  if (isTRUE(d$returning)) {
    return(returning())
  }
  if (isFALSE(d$returning)) {
    return(two_step())
  }

  tryCatch(returning(), error = \(err) two_step())
}

#' Insert one row, discarding any generated key
#' @noRd
insert_row <- \(con, table, values) {
  row <- quoted_row(con, values)
  dbExecute(con, paste0(
    "INSERT INTO ", dbQuoteIdentifier(con, table),
    " (", row$columns, ") VALUES (", row$values, ")"
  ))
}

#' Update columns of a single row matched on its primary key
#' @noRd
update_row <- \(con, table, values, id_column, id) {
  assignments <- paste(
    vapply(
      names(values),
      \(column) {
        paste(
          dbQuoteIdentifier(con, column),
          "=",
          dbQuoteLiteral(con, values[[column]])
        )
      },
      ""
    ),
    collapse = ", "
  )

  dbExecute(con, paste0(
    "UPDATE ", dbQuoteIdentifier(con, table),
    " SET ", assignments,
    " WHERE ", dbQuoteIdentifier(con, id_column),
    " = ", dbQuoteLiteral(con, id)
  ))
}

#' Create a table and its indexes, if the table is not already there
#' @noRd
create_table <- \(con, table, columns, indexes = list(), pre_ddl = character(0)) {
  if (dbExistsTable(con, table)) {
    return(invisible(FALSE))
  }

  for (statement in pre_ddl) dbExecute(con, statement)

  dbExecute(con, paste0(
    "CREATE TABLE ", dbQuoteIdentifier(con, table),
    " (\n  ", paste(columns, collapse = ",\n  "), "\n)"
  ))

  # Indexes are created here rather than with IF NOT EXISTS, which MySQL lacks
  for (name in names(indexes)) {
    dbExecute(con, paste0(
      "CREATE INDEX ", dbQuoteIdentifier(con, name),
      " ON ", dbQuoteIdentifier(con, table),
      " (", paste(dbQuoteIdentifier(con, indexes[[name]]), collapse = ", "), ")"
    ))
  }

  invisible(TRUE)
}

#' Create the survey schema on a connection
#'
#' Safe to call on every startup: existing tables are left alone.
#'
#' @param con Database connection from any DBI driver
#' @param quiet Suppress the success message
#' @return The connection, invisibly
#' @export
init_database <- \(con, quiet = FALSE) {
  d <- dialect_for(con)
  on_connect(con)

  created <- create_table(
    con,
    "sessions",
    c(
      d$serial_pk("sessions", "session_id"),
      "started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
      "completed_at TIMESTAMP",
      "completed BOOLEAN NOT NULL DEFAULT FALSE",
      "retry_count INTEGER DEFAULT 0",
      "question_set_version TEXT DEFAULT '1.0'",
      "duration_seconds INTEGER"
    ),
    indexes = list(
      idx_sessions_completed = "completed",
      idx_sessions_started = "started_at"
    ),
    pre_ddl = d$pre_ddl("sessions", "session_id")
  )

  create_table(
    con,
    "responses",
    c(
      d$serial_pk("responses", "response_id"),
      "session_id INTEGER NOT NULL",
      "question_id TEXT NOT NULL",
      "question_order INTEGER NOT NULL",
      "question_text TEXT",
      "input_raw TEXT NOT NULL",
      "input_extracted TEXT",
      "answered_clearly BOOLEAN",
      "responded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
      "retry_attempt INTEGER DEFAULT 0",
      "question_duration_seconds INTEGER",
      if (d$foreign_keys) {
        paste0(
          "FOREIGN KEY (session_id) REFERENCES sessions(session_id)",
          d$fk_cascade
        )
      }
    ),
    indexes = list(
      idx_responses_session = "session_id",
      idx_responses_question = "question_id",
      idx_responses_order = c("session_id", "question_order")
    ),
    pre_ddl = d$pre_ddl("responses", "response_id")
  )

  if (created && !quiet) {
    cli_alert_success("Survey schema created on {.val {class(con)[1]}}")
  }

  invisible(con)
}

#' Start a new survey session
#' @param con Database connection
#' @param version Question set version
#' @return session_id
#' @export
start_session <- \(con, version = "1.0") {
  insert_returning_id(
    con,
    "sessions",
    list(question_set_version = as.character(version)),
    "session_id"
  )
}

#' Save a question response
#' @param con Database connection
#' @param session_id Integer session ID
#' @param question_id Question identifier
#' @param question_order Order in survey
#' @param question_text Actual question text shown
#' @param input_raw User's raw input
#' @param input_extracted Cleaned/extracted value
#' @param answered_clearly Boolean quality flag
#' @param retry_attempt Which attempt (0 = first)
#' @param question_duration_seconds Duration in seconds for this question
#' @export
save_response <- \(con, session_id, question_id, question_order, question_text,
  input_raw, input_extracted = NULL, answered_clearly = NULL,
  retry_attempt = 0, question_duration_seconds = NULL) {
  insert_row(con, "responses", list(
    session_id = as.integer(session_id),
    question_id = as.character(question_id),
    question_order = as.integer(question_order),
    question_text = as.character(question_text),
    input_raw = as.character(input_raw),
    input_extracted = as.character(input_extracted),
    answered_clearly = as.logical(answered_clearly),
    retry_attempt = as.integer(retry_attempt),
    question_duration_seconds = as.integer(question_duration_seconds)
  ))
}

#' Update how long a session has been running
#'
#' The duration is measured in R rather than with SQL date arithmetic, whose
#' functions differ on every backend.
#'
#' @param con Database connection
#' @param session_id Integer session ID
#' @param duration_seconds Elapsed seconds since the session started
#' @export
update_session_duration <- \(con, session_id, duration_seconds) {
  update_row(
    con,
    "sessions",
    list(duration_seconds = as.integer(duration_seconds)),
    "session_id",
    as.integer(session_id)
  )
}

#' Mark session as completed
#' @param con Database connection
#' @param session_id Integer session ID
#' @param duration_seconds Elapsed seconds since the session started
#' @export
complete_session <- \(con, session_id, duration_seconds) {
  update_row(
    con,
    "sessions",
    list(
      completed = TRUE,
      completed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      duration_seconds = as.integer(duration_seconds)
    ),
    "session_id",
    as.integer(session_id)
  )
}

#' Increment retry count for session
#' @param con Database connection
#' @param session_id Integer session ID
#' @export
increment_retry <- \(con, session_id) {
  target <- dbQuoteIdentifier(con, "sessions")
  id <- dbQuoteIdentifier(con, "session_id")
  column <- dbQuoteIdentifier(con, "retry_count")

  dbExecute(con, paste0(
    "UPDATE ", target,
    " SET ", column, " = ", column, " + 1",
    " WHERE ", id, " = ", dbQuoteLiteral(con, as.integer(session_id))
  ))
}
