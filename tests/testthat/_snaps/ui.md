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
      <div class="sb-complete sb-locked" role="status">
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
      i The examples are "icecream".

