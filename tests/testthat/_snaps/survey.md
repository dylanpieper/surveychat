# a failed intro shows the question alone

    Code
      message <- engine$process_input("Ana")$message
    Condition
      Warning:
      Content generation failed for question "flavor".
      Caused by error:
      ! API down

# a failed adaptive question is skipped

    Code
      result <- engine$process_input("mint")
    Condition
      Warning:
      Content generation failed for question "why".
      Caused by error in `generate_content()`:
      ! The LLM returned no text.

# a failed extraction asks again and does not count as a retry

    Code
      failed <- engine$process_input("Ana")
    Condition
      Warning:
      Could not process the reply to question "name".
      Caused by error:
      ! rate limited

# a failed bookkeeping write does not stop or repeat the survey

    Code
      invisible(engine$process_input("Ana"))
    Condition
      Warning:
      Could not update the session duration of session 1; the survey continues.
      Caused by error in `update_session_duration()`:
      ! database busy
    Code
      invisible(engine$process_input("mint"))
    Condition
      Warning:
      Could not update the session duration of session 1; the survey continues.
      Caused by error in `update_session_duration()`:
      ! database busy
    Code
      last <- engine$process_input("fresh")
    Condition
      Warning:
      Could not update the session duration of session 1; the survey continues.
      Caused by error in `update_session_duration()`:
      ! database busy
      Warning:
      Could not update the completion of session 1; the survey continues.
      Caused by error in `complete_session()`:
      ! database busy

# a failed retry count still asks again and counts the retry

    Code
      retry <- engine$process_input("?")
    Condition
      Warning:
      Could not update the retry count of session 1; the survey continues.
      Caused by error in `increment_retry()`:
      ! database busy

