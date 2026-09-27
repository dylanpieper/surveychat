# init_database() rejects a responses table from before 0.1.0

    Code
      init_database(con)
    Condition
      Error in `init_database()`:
      ! The responses table has no column valid.
      i This database is from before surveychat 0.1.0. Rename answered_clearly to valid, or use a new database.

