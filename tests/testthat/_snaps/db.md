# init_database() rejects a responses table from before 0.1.0

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no column valid.
      i This database is from an earlier version of surveychat. Rename answered_clearly to valid, or use a new database.

# init_database() gives renames for the input_* columns

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no columns answer_raw, answer_extracted, and duration_seconds.
      i This database is from an earlier version of surveychat. Rename input_raw to answer_raw, input_extracted to answer_extracted, and question_duration_seconds to duration_seconds, or use a new database.

