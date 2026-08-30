#' Database setup and operations
box::use(
  DBI[dbConnect, dbDisconnect, dbExecute, dbGetQuery],
  cli[cli_alert_success],
)

#' Initialize SQLite database with schema
#' @param db_path Path to database file
#' @param db_driver Database driver (default RSQLite::SQLite())
#' @export
init_database <- \(db_path = "survey.db", db_driver = RSQLite::SQLite()) {
  con <- dbConnect(db_driver, db_path)

  dbExecute(con, "PRAGMA foreign_keys = ON")

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS sessions (
      session_id INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      completed_at TIMESTAMP,
      completed BOOLEAN NOT NULL DEFAULT FALSE,
      retry_count INTEGER DEFAULT 0,
      question_set_version TEXT DEFAULT '1.0',
      duration_seconds INTEGER
    )
  ")

  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_sessions_completed ON sessions(completed)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at)")

  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS responses (
      response_id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL,
      question_id TEXT NOT NULL,
      question_order INTEGER NOT NULL,
      question_text TEXT,
      input_raw TEXT NOT NULL,
      input_extracted TEXT,
      answered_clearly BOOLEAN,
      responded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      retry_attempt INTEGER DEFAULT 0,
      question_duration_seconds INTEGER,

      FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
    )
  ")

  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_responses_session ON responses(session_id)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_responses_question ON responses(question_id)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_responses_order ON responses(session_id, question_order)")

  dbDisconnect(con)
  cli_alert_success("Database initialized at {.file {db_path}}")
}

#' Open a connection to the survey database
#' @param db_path Path to database file
#' @param db_driver Database driver
#' @return Database connection
#' @export
connect <- \(db_path = "survey.db", db_driver = RSQLite::SQLite()) {
  dbConnect(db_driver, db_path)
}

#' Close a database connection
#' @param con Database connection
#' @export
disconnect <- \(con) {
  dbDisconnect(con)
}

#' Start a new survey session
#' @param con Database connection
#' @param version Question set version
#' @return session_id
#' @export
start_session <- \(con, version = "1.0") {
  dbExecute(
    con,
    "INSERT INTO sessions (question_set_version) VALUES (?)",
    params = list(version)
  )

  dbGetQuery(con, "SELECT last_insert_rowid() as id")$id
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
  dbExecute(
    con,
    "INSERT INTO responses
     (session_id, question_id, question_order, question_text, input_raw,
      input_extracted, answered_clearly, retry_attempt, question_duration_seconds)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      as.integer(session_id),
      as.character(question_id),
      as.integer(question_order),
      as.character(question_text),
      as.character(input_raw),
      if (is.null(input_extracted)) NULL else as.character(input_extracted),
      if (is.null(answered_clearly)) NULL else as.logical(answered_clearly),
      as.integer(retry_attempt),
      if (is.null(question_duration_seconds)) {
        NULL
      } else {
        as.integer(question_duration_seconds)
      }
    )
  )
}

#' Update session duration
#' @param con Database connection
#' @param session_id Integer session ID
#' @export
update_session_duration <- \(con, session_id) {
  dbExecute(
    con,
    "UPDATE sessions SET
       duration_seconds = CAST((julianday(CURRENT_TIMESTAMP) - julianday(started_at)) * 86400 AS INTEGER)
     WHERE session_id = ?",
    params = list(session_id)
  )
}

#' Mark session as completed
#' @param con Database connection
#' @param session_id Integer session ID
#' @export
complete_session <- \(con, session_id) {
  dbExecute(
    con,
    "UPDATE sessions SET
       completed = TRUE,
       completed_at = CURRENT_TIMESTAMP,
       duration_seconds = CAST((julianday(CURRENT_TIMESTAMP) - julianday(started_at)) * 86400 AS INTEGER)
     WHERE session_id = ?",
    params = list(session_id)
  )
}

#' Increment retry count for session
#' @param con Database connection
#' @param session_id Integer session ID
#' @export
increment_retry <- \(con, session_id) {
  dbExecute(
    con,
    "UPDATE sessions SET retry_count = retry_count + 1 WHERE session_id = ?",
    params = list(session_id)
  )
}
