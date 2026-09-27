# init_database() rejects a responses table from before 0.1.0

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no column valid.
      i Use a new database, or change this one:
      * Rename answered_clearly to valid.

# init_database() gives renames for the input_* columns

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no columns answer_raw, answer_extracted, and duration_seconds.
      i Use a new database, or change this one:
      * Rename input_raw to answer_raw, input_extracted to answer_extracted, and question_duration_seconds to duration_seconds.

# init_database() gives only renames that supply a missing column

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no column retry_attempt.
      i Use a new database, or change this one:
      * Add retry_attempt.

