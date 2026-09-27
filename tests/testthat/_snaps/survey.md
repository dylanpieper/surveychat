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

