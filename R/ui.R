# UI for the chat survey

styles <- "
.sb-progress { display: flex; align-items: center; gap: .5rem; }
.sb-progress-track {
  width: 72px; height: 4px; border-radius: 2px; overflow: hidden;
  background: var(--bs-secondary-bg, #e9ecef);
}
.sb-progress-fill {
  height: 100%; border-radius: 2px; transition: width .35s ease;
  background: var(--bs-primary, #0d6efd);
}
.sb-progress-label {
  font-size: .8rem; font-weight: 400; white-space: nowrap;
  color: var(--bs-secondary-color, #6c757d);
}
.sb-complete {
  display: flex; align-items: center; justify-content: center; gap: .5rem;
  padding: .75rem 1rem; margin: 0 auto; width: min(680px, 100%);
  border-top: 1px solid var(--bs-border-color, #dee2e6);
  color: var(--bs-secondary-color, #6c757d);
}
.sb-complete-icon { color: var(--bs-success, #198754); font-weight: 700; }
"

#' @rdname survey_server
#' @param title The title in the card header.
#' @return `survey_ui()` returns a full-page Shiny UI with the chat, a progress
#'   cue, and a footer that shows the closing message.
#' @export
survey_ui <- function(id, title = "Survey") {
  ns <- shiny::NS(id)
  bslib::page_fillable(
    fillable_mobile = TRUE,
    htmltools::tags$head(htmltools::tags$style(htmltools::HTML(styles))),
    bslib::card(
      bslib::card_header(
        htmltools::div(
          class = "d-flex justify-content-between align-items-center gap-3",
          htmltools::span(title),
          shiny::uiOutput(ns("progress"), inline = TRUE)
        )
      ),
      shinychat::chat_ui(id = ns("chat")),
      shiny::uiOutput(ns("footer"))
    )
  )
}

# Progress cue: a thin bar and "Question {current} of {total}"
survey_progress <- function(
  current,
  total,
  complete = FALSE,
  label = "Question {current} of {total}",
  complete_label = "Complete"
) {
  percent <- if (complete || total == 0) 100 else 100 * (current - 1) / total
  text <- if (complete) {
    complete_label
  } else {
    interpolate(label, list(current = current, total = total))
  }

  htmltools::div(
    class = "sb-progress",
    htmltools::div(
      class = "sb-progress-track",
      role = "progressbar",
      `aria-valuenow` = round(percent),
      `aria-valuemin` = 0,
      `aria-valuemax` = 100,
      `aria-label` = text,
      htmltools::div(
        class = "sb-progress-fill",
        style = paste0("width: ", round(percent, 1), "%;")
      )
    ),
    htmltools::span(class = "sb-progress-label", text)
  )
}

# Footer that retires the chat input after the survey. The chat re-enables its
# own input at the end of each stream, so a style rule hides the input instead
# of the `disabled` property. `chat_id` is the full, namespaced id.
survey_complete <- function(message, chat_id) {
  htmltools::tagList(
    htmltools::tags$style(htmltools::HTML(sprintf(
      "#%s shiny-chat-input { display: none; }",
      chat_id
    ))),
    htmltools::div(
      class = "sb-complete",
      role = "status",
      htmltools::span(class = "sb-complete-icon", "\u2713"),
      htmltools::span(message)
    )
  )
}
