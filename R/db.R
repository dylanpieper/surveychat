# Database setup and operations
#
# Every statement here is built from DBI primitives and the dialect table, so
# the same code runs against any driver. Three rules keep it portable:
#
# - Identifiers and values pass through `dbQuoteIdentifier()` and
#   `dbQuoteLiteral()`, never through `?` or `$1` placeholders, whose syntax
#   differs by driver.
# - The schema is built from `dialect_for()` fragments instead of literal DDL.
# - Dates and durations are computed in R, never with SQL date functions.

#' Quote a named list of values as a `(columns) VALUES (values)` pair
#' @noRd
quoted_row <- function(con, values) {
  # NULL and the zero-length results of as.character(NULL) both mean SQL NULL
  values <- lapply(values, \(value) if (length(value) == 0) NA else value)
  list(
    columns = DBI::SQL(paste(
      DBI::dbQuoteIdentifier(con, names(values)),
      collapse = ", "
    )),
    values = DBI::SQL(paste(
      vapply(
        values,
        \(value) as.character(DBI::dbQuoteLiteral(con, value)),
        ""
      ),
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
insert_returning_id <- function(con, table, values, id_column) {
  d <- dialect_for(con)
  row <- quoted_row(con, values)
  target <- DBI::dbQuoteIdentifier(con, table)
  id <- DBI::dbQuoteIdentifier(con, id_column)
  insert <- paste0(
    "INSERT INTO ",
    target,
    " (",
    row$columns,
    ") VALUES (",
    row$values,
    ")"
  )

  returning <- \() {
    DBI::dbGetQuery(con, paste0(insert, " RETURNING ", id, " AS id"))$id
  }

  two_step <- \() {
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con, insert)
      DBI::dbGetQuery(con, d$last_id(table, id_column))$id
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
insert_row <- function(con, table, values) {
  row <- quoted_row(con, values)
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO ",
      DBI::dbQuoteIdentifier(con, table),
      " (",
      row$columns,
      ") VALUES (",
      row$values,
      ")"
    )
  )
}

#' Update columns of a single row matched on its primary key
#' @noRd
update_row <- function(con, table, values, id_column, id) {
  assignments <- paste(
    vapply(
      names(values),
      \(column) {
        paste(
          DBI::dbQuoteIdentifier(con, column),
          "=",
          DBI::dbQuoteLiteral(con, values[[column]])
        )
      },
      ""
    ),
    collapse = ", "
  )

  DBI::dbExecute(
    con,
    paste0(
      "UPDATE ",
      DBI::dbQuoteIdentifier(con, table),
      " SET ",
      assignments,
      " WHERE ",
      DBI::dbQuoteIdentifier(con, id_column),
      " = ",
      DBI::dbQuoteLiteral(con, id)
    )
  )
}

#' Create a table and its indexes, if the table is not already there
#' @noRd
create_table <- function(
  con,
  table,
  columns,
  indexes = list(),
  pre_ddl = character(0)
) {
  if (DBI::dbExistsTable(con, table)) {
    return(invisible(FALSE))
  }

  for (statement in pre_ddl) {
    DBI::dbExecute(con, statement)
  }

  DBI::dbExecute(
    con,
    paste0(
      "CREATE TABLE ",
      DBI::dbQuoteIdentifier(con, table),
      " (\n  ",
      paste(columns, collapse = ",\n  "),
      "\n)"
    )
  )

  # Indexes are created here rather than with IF NOT EXISTS, which MySQL lacks
  for (name in names(indexes)) {
    DBI::dbExecute(
      con,
      paste0(
        "CREATE INDEX ",
        DBI::dbQuoteIdentifier(con, name),
        " ON ",
        DBI::dbQuoteIdentifier(con, table),
        " (",
        paste(DBI::dbQuoteIdentifier(con, indexes[[name]]), collapse = ", "),
        ")"
      )
    )
  }

  invisible(TRUE)
}

# Returns a DBI connection for `con`. A pool lends one connection until the
# frame `env` exits, so every statement of one operation uses the same
# connection: the dialect lookup, a transaction, and the id lookup after it.
checkout <- function(con, env = parent.frame()) {
  if (inherits(con, "Pool")) {
    rlang::check_installed(
      "pool",
      "to use a connection pool.",
      version = "1.0.0"
    )
    return(pool::localCheckout(con, env))
  }
  con
}

#' Create the survey schema on a connection
#'
#' Makes the `sessions` and `responses` tables and their indexes. It is safe to
#' call on every start, because it leaves existing tables alone.
#' [survey_server()] calls it for you; call it yourself to make the tables
#' before the first user arrives.
#'
#' @param con A connection from any DBI driver, or a `pool::dbPool()`.
#' @param quiet If `TRUE`, show no message when the tables are made.
#' @return `con`, invisibly.
#' @export
#' @examplesIf rlang::is_installed("RSQLite")
#' con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' init_database(con)
#' DBI::dbListTables(con)
#' DBI::dbDisconnect(con)
init_database <- function(con, quiet = FALSE) {
  target <- con
  con <- checkout(con)
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
      "version TEXT DEFAULT '1.0'",
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
      "answer_raw TEXT NOT NULL",
      "answer_extracted TEXT",
      "valid BOOLEAN",
      "responded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
      "retry_attempt INTEGER DEFAULT 0",
      "duration_seconds INTEGER",
      "method TEXT",
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

  check_columns(con, "sessions")
  check_columns(con, "responses")

  if (created && !quiet) {
    cli::cli_alert_success("Survey schema created on {.val {class(con)[1]}}")
  }

  invisible(target)
}

# An existing table must have every column that the survey writes. Otherwise
# the first write would fail partway through a survey.
check_columns <- function(con, table, call = rlang::caller_env()) {
  fields <- DBI::dbListFields(con, table)
  missing <- setdiff(written_columns[[table]], fields)
  if (length(missing) == 0) {
    return(invisible(con))
  }
  renamed <- renamed_columns[[table]]
  old <- names(renamed)[names(renamed) %in% fields & renamed %in% missing]
  renames <- paste(old, "to", renamed[old])
  added <- setdiff(missing, renamed[old])
  cli::cli_abort(
    c(
      "The {.field {table}} table has no {cli::qty(missing)}column{?s} {.field {missing}}.",
      "i" = "Use a new database, or change this one:",
      "*" = if (length(old) > 0) "Rename {renames}.",
      "*" = if (length(added) > 0) "Add {.field {added}}."
    ),
    call = call
  )
}

# The columns that the survey writes to each table
written_columns <- list(
  sessions = c(
    "completed_at",
    "completed",
    "retry_count",
    "version",
    "duration_seconds"
  ),
  responses = c(
    "session_id",
    "question_id",
    "question_order",
    "question_text",
    "answer_raw",
    "answer_extracted",
    "valid",
    "retry_attempt",
    "duration_seconds",
    "method"
  )
)

# Old column names and their current names, for each table
renamed_columns <- list(
  sessions = c(question_set_version = "version"),
  responses = c(
    answered_clearly = "valid",
    input_raw = "answer_raw",
    input_extracted = "answer_extracted",
    question_duration_seconds = "duration_seconds"
  )
)

# Row operations ----
# Each takes a connection or a pool and computes dates and durations in R,
# because SQL date functions differ on every backend.

# Opens a session row and returns its generated session_id
start_session <- function(con, version = "1.0") {
  con <- checkout(con)
  insert_returning_id(
    con,
    "sessions",
    list(version = as.character(version)),
    "session_id"
  )
}

# Writes one reply; NULL values become SQL NULL
save_response <- function(
  con,
  session_id,
  question_id,
  question_order,
  question_text,
  answer_raw,
  answer_extracted = NULL,
  valid = NULL,
  retry_attempt = 0,
  duration_seconds = NULL,
  method = NULL
) {
  if (!is.null(method) && !rlang::is_string(method, c("chat", "form"))) {
    cli::cli_abort(
      "{.arg method} must be {.val chat} or {.val form}, not {.obj_type_friendly {method}}."
    )
  }
  con <- checkout(con)
  insert_row(
    con,
    "responses",
    list(
      session_id = as.integer(session_id),
      question_id = as.character(question_id),
      question_order = as.integer(question_order),
      question_text = as.character(question_text),
      answer_raw = as.character(answer_raw),
      answer_extracted = as.character(answer_extracted),
      valid = as.logical(valid),
      retry_attempt = as.integer(retry_attempt),
      duration_seconds = as.integer(duration_seconds),
      method = as.character(method)
    )
  )
}

update_session_duration <- function(con, session_id, duration_seconds) {
  con <- checkout(con)
  update_row(
    con,
    "sessions",
    list(duration_seconds = as.integer(duration_seconds)),
    "session_id",
    as.integer(session_id)
  )
}

complete_session <- function(con, session_id, duration_seconds) {
  con <- checkout(con)
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

increment_retry <- function(con, session_id) {
  con <- checkout(con)
  target <- DBI::dbQuoteIdentifier(con, "sessions")
  id <- DBI::dbQuoteIdentifier(con, "session_id")
  column <- DBI::dbQuoteIdentifier(con, "retry_count")

  DBI::dbExecute(
    con,
    paste0(
      "UPDATE ",
      target,
      " SET ",
      column,
      " = ",
      column,
      " + 1",
      " WHERE ",
      id,
      " = ",
      DBI::dbQuoteLiteral(con, as.integer(session_id))
    )
  )
}
