#' UI for the chat survey

box::use(
  bslib[card, card_header, page_fillable],
  htmltools[HTML, div, span, tagList, tags],
  shiny[uiOutput],
  shinychat[chat_ui],
  R/utils[interpolate],
)

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

#' Chat survey page
#' @param title Card header title
#' @param chat_id ID of the chat element
#' @param progress_id Output ID of the progress cue
#' @param footer_id Output ID of the completion footer
#' @return A Shiny UI definition
#' @export
survey_ui <- \(title = "SurveyChat",
               chat_id = "chat",
               progress_id = "survey_progress",
               footer_id = "survey_footer") {
  page_fillable(
    fillable_mobile = TRUE,
    tags$head(tags$style(HTML(styles))),
    card(
      card_header(
        div(
          class = "d-flex justify-content-between align-items-center gap-3",
          span(title),
          uiOutput(progress_id, inline = TRUE)
        )
      ),
      chat_ui(id = chat_id),
      uiOutput(footer_id)
    )
  )
}

#' Progress cue for the current question
#' @param current Current question number
#' @param total Total number of questions
#' @param complete Whether the survey has finished
#' @param label Label template with {current} and {total} placeholders
#' @param complete_label Label shown once the survey has finished
#' @return A Shiny UI definition
#' @export
survey_progress <- \(current,
                     total,
                     complete = FALSE,
                     label = "Question {current} of {total}",
                     complete_label = "Complete") {
  percent <- if (complete || total == 0) 100 else 100 * (current - 1) / total
  text <- if (complete) {
    complete_label
  } else {
    interpolate(label, list(current = current, total = total))
  }

  div(
    class = "sb-progress",
    div(
      class = "sb-progress-track",
      role = "progressbar",
      `aria-valuenow` = round(percent),
      `aria-valuemin` = 0,
      `aria-valuemax` = 100,
      `aria-label` = text,
      div(class = "sb-progress-fill", style = paste0("width: ", round(percent, 1), "%;"))
    ),
    span(class = "sb-progress-label", text)
  )
}

#' Footer that retires the chat input once the survey has finished
#'
#' The chat component re-enables its own input at the end of every stream, so
#' the input is retired with a style rule rather than the `disabled` property.
#' @param message Closing message shown in place of the input
#' @param chat_id ID of the chat element whose input is retired
#' @return A Shiny UI definition
#' @export
survey_complete <- \(message, chat_id = "chat") {
  tagList(
    tags$style(HTML(sprintf(
      "#%s shiny-chat-input { display: none; }", chat_id
    ))),
    div(
      class = "sb-complete",
      role = "status",
      span(class = "sb-complete-icon", "✓"),
      span(message)
    )
  )
}
