# the progress cue shows the question and the bar width

    Code
      cat(as.character(survey_progress(2, 4)))
    Output
      <div class="sb-progress">
        <div class="sb-progress-track" role="progressbar" aria-valuenow="25" aria-valuemin="0" aria-valuemax="100" aria-label="Question 2 of 4">
          <div class="sb-progress-fill" style="width: 25%;"></div>
        </div>
        <span class="sb-progress-label">Question 2 of 4</span>
      </div>

---

    Code
      cat(as.character(survey_progress(4, 4, complete = TRUE)))
    Output
      <div class="sb-progress">
        <div class="sb-progress-track" role="progressbar" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100" aria-label="Complete">
          <div class="sb-progress-fill" style="width: 100%;"></div>
        </div>
        <span class="sb-progress-label">Complete</span>
      </div>

# the footer hides the namespaced chat input

    Code
      cat(as.character(survey_complete("Done", "survey-chat")))
    Output
      <style>#survey-chat shiny-chat-input { display: none; }</style>
      <div class="sb-complete" role="status">
        <span class="sb-complete-icon">✓</span>
        <span>Done</span>
      </div>

---

    Code
      cat(as.character(survey_complete("Unavailable", "survey-chat", status = "locked")))
    Output
      <style>#survey-chat shiny-chat-input { display: none; }</style>
      <div class="sb-overlay sb-locked" role="status">
        <span class="sb-complete-icon">✕</span>
        <span>Unavailable</span>
      </div>

# survey_chat_ui() checks its arguments

    Code
      survey_chat_ui("survey", drawer = TRUE)
    Condition
      Error in `survey_chat_ui()`:
      ! `drawer` must be `FALSE` or a `shinychat::chat_drawer()`, not `TRUE`.

---

    Code
      survey_chat_ui("survey", progress = "yes")
    Condition
      Error in `survey_chat_ui()`:
      ! `progress` must be `TRUE` or `FALSE`, not a string.

# run_example() lists the examples and rejects an unknown name

    Code
      run_example("nope")
    Condition
      Error in `run_example()`:
      ! There is no example named "nope".
      i The examples are "demographics" or "icecream".

# example_chat() passes a Chat through and rejects other values

    Code
      example_chat(NULL)
    Condition
      Error:
      ! No chat is set for the example.
      i Set `chat`, such as `chat = "openai/gpt-4.1-mini"`, or set the environment variable `SURVEYCHAT_MODEL`.

---

    Code
      example_chat(1)
    Condition
      Error:
      ! `chat` must be a string, an ellmer chat, or `NULL`.
      i A string is "provider/model" or "provider".
      x You supplied a number.

# run_example() stops before runApp() when the credentials fail

    Code
      run_example(chat = chat)
    Condition
      Error in `run_example()`:
      ! The chat is not set up.
      i Check the credentials of the provider, such as its API key in '~/.Renviron', then restart R.
      Caused by error in `credentials()`:
      ! no key

