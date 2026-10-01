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
  padding: .5rem 0; font-size: 1rem;
}
.sb-complete-icon { color: var(--bs-success, #198754); font-weight: 700; }
.sb-locked .sb-complete-icon { color: var(--bs-danger, #dc3545); }
.sb-toolbar {
  display: flex; align-items: center; justify-content: space-between;
  gap: .75rem; width: 100%;
}
.sb-chat .shiny-chat-drawer-trigger { display: none; }
.sb-chat .shiny-chat-suggestion-list[data-pending]::before { content: none; }
shiny-chat-container.sb-chat { position: relative; }
/* A sidebar with no title puts its collapse toggle over the first message */
.sidebar-content:not(:has(> .sidebar-title)) > shiny-chat-container.sb-chat {
  padding-top: 2.5rem;
}
/* shinychat adds a top inset for its drawer button once the drawer has
   content. The button is hidden here, so the inset only adds empty space */
shiny-chat-container.sb-chat .shiny-chat-messages { padding-block-start: 0; }
.sb-overlay {
  position: absolute; inset: 0; z-index: 10;
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: .75rem; padding: 1rem; text-align: center;
  background: var(--bs-body-bg, #fff);
}
.sb-waiter { font-size: .9rem; color: var(--bs-secondary-color, #6c757d); }
.sb-locked .sb-complete-icon { font-size: 1.5rem; }
.sb-chat:has(.sb-overlay) shiny-chat-input { display: none; }
/* In a fill container, the chat must shrink so that its messages scroll and
   follow new content (posit-dev/shinychat#407) */
shiny-chat-container.sb-chat[fill] { min-height: 0; }
.sb-panel { min-height: 28rem; }
/* The fill container is a column; side by side needs a row */
.sb-views.html-fill-container { flex-direction: row; gap: 0; }
.sb-views > .sb-view.html-fill-item { flex: 1 1 0; width: auto; }
/* The chat sets an inline zero padding on its fill parents; only
   !important wins over an inline style */
.sb-views > .sb-view-chat { padding: .5rem .75rem .75rem !important; }
/* Side by side: a light overlay dims the pane that the user is not using.
   Hover picks the active pane, else focus. Clicks pass through. */
.sb-views > .sb-view { position: relative; }
.sb-views > .sb-view::after {
  content: ''; position: absolute; inset: 0; z-index: 20;
  pointer-events: none; opacity: 0; transition: opacity .2s ease;
  background: var(--bs-card-bg, var(--bs-body-bg, #fff));
}
.sb-views:has(> .sb-view:hover) > .sb-view:not(:hover)::after,
.sb-views:not(:has(> .sb-view:hover)):focus-within
  > .sb-view:not(:focus-within)::after {
  opacity: .55;
}
/* Side by side: a line between the form and the chat while both show */
.sb-view-form:not([style*='display: none']) + .sb-view-chat {
  border-left: 1px solid var(--bs-border-color-translucent, rgba(0,0,0,.1));
}
@media (max-width: 767.98px) {
  .sb-views.html-fill-container { flex-direction: column; }
  .sb-view-form:not([style*='display: none']) + .sb-view-chat {
    border-left: 0;
    border-top: 1px solid var(--bs-border-color-translucent, rgba(0,0,0,.1));
  }
}
.sb-view-pick .btn {
  color: inherit; border: 1px solid currentColor; opacity: .7;
  --bs-btn-padding-x: .55rem;
}
.sb-view-pick .btn:hover { opacity: 1; }
.sb-view-pick .btn-check:checked + .btn {
  opacity: 1; color: inherit; border-color: currentColor;
  background-color: color-mix(in srgb, currentColor 18%, transparent);
}
.sb-view-pick .btn-check:focus-visible + .btn {
  outline: 2px solid currentColor; outline-offset: 2px;
}
.sb-form { position: relative; min-height: 12rem; overflow-y: auto; }
.sb-form-intro { color: var(--bs-secondary-color, #6c757d); }
.sb-form .shiny-input-container { width: 100%; }
.sb-form .sb-overlay.sb-locked { position: static; }
.sb-form .sb-complete p { margin: 0; }
"

#' @rdname survey_server
#' @param title The title in the card header.
#' @return `survey_ui()` returns a full-page Shiny UI with the
#'   [survey_panel_ui()] card.
#' @export
survey_ui <- function(id, title = "Survey") {
  bslib::page_fillable(
    fillable_mobile = TRUE,
    survey_panel_ui(id, title = title)
  )
}

#' Put the survey card in any page
#'
#' `survey_panel_ui()` is a card with the title, the progress cue, the chat,
#' and the form. With one method in `set_config(methods = )`, the card shows
#' that view. With both, it starts side by side, and the header has three
#' icon buttons: side by side, the form, and the AI chat. On a narrow screen,
#' the side-by-side view puts the chat below the form. Pair it with
#' [survey_server()] with the same `id`.
#'
#' The card fills its container. In a page that does not fill the window,
#' put it in a [bslib::as_fill_carrier()] with a height.
#'
#' @inheritParams survey_chat_ui
#' @param title The title in the card header, or `NULL` for no title. With
#'   no title, the view buttons are on the left and the progress cue on the
#'   right.
#' @return A [bslib::card()].
#' @seealso [survey_chat_ui()] for the chat alone. The `"demographics"`
#'   example of [run_example()] puts the card in a narrow page.
#' @export
#' @examplesIf interactive() && rlang::is_installed("RSQLite")
#' library(shiny)
#' library(bslib)
#'
#' ui <- page_fixed(
#'   as_fill_carrier(div(
#'     style = "max-width: 640px; height: 80vh; margin: 2rem auto;",
#'     survey_panel_ui("survey")
#'   ))
#' )
survey_panel_ui <- function(id, title = NULL) {
  ns <- shiny::NS(id)
  if (!is.null(title)) {
    check_string(title)
  }
  controls <- htmltools::tagList(
    shiny::uiOutput(ns("method"), inline = TRUE),
    shiny::uiOutput(ns("progress"), inline = TRUE)
  )
  bslib::card(
    class = "sb-panel",
    bslib::card_header(
      htmltools::div(
        class = "d-flex justify-content-between align-items-center gap-3 w-100",
        if (is.null(title)) {
          controls
        } else {
          htmltools::tagList(
            htmltools::span(title),
            htmltools::div(class = "d-flex align-items-center gap-3", controls)
          )
        }
      )
    ),
    htmltools::bindFillRole(
      htmltools::div(
        class = "sb-views",
        survey_view(
          ns,
          "form",
          bslib::card_body(class = "sb-form", shiny::uiOutput(ns("form")))
        ),
        survey_view(ns, "chat", survey_chat_ui(id, progress = FALSE))
      ),
      container = TRUE,
      item = TRUE
    )
  )
}

# A panel that shows while `output.view` is `view` or "both". Both panels
# stay hidden until the server sends the view, so the wrong one never
# flashes.
survey_view <- function(ns, view, content) {
  htmltools::bindFillRole(
    htmltools::div(
      class = paste0("sb-view sb-view-", view),
      `data-display-if` = sprintf(
        "output.view === '%s' || output.view === 'both'",
        view
      ),
      `data-ns-prefix` = ns(""),
      content
    ),
    container = TRUE,
    item = TRUE
  )
}

# The views that the header buttons choose, as `list(value, label, icon)`
view_choices <- list(
  list("both", "Side by side", "table-columns"),
  list("form", "Form", "list-check"),
  list("chat", "AI chat", "robot")
)

# Three icon buttons that choose the view. They are one Shiny radio group,
# so the browser keeps the active button and the server reads `input$<id>`.
view_picker <- function(id, selected) {
  buttons <- lapply(view_choices, \(choice) {
    button_id <- paste0(id, "-", choice[[1]])
    htmltools::tagList(
      htmltools::tags$input(
        type = "radio",
        class = "btn-check",
        name = id,
        id = button_id,
        value = choice[[1]],
        autocomplete = "off",
        checked = if (choice[[1]] == selected) NA
      ),
      htmltools::tags$label(
        class = "btn",
        `for` = button_id,
        title = choice[[2]],
        `aria-label` = choice[[2]],
        shiny::icon(choice[[3]])
      )
    )
  })
  htmltools::div(
    id = id,
    class = "shiny-input-radiogroup btn-group btn-group-sm sb-view-pick",
    role = "radiogroup",
    `aria-label` = "View",
    buttons
  )
}

#' Put the survey chat in any page
#'
#' `survey_chat_ui()` is the survey chat alone, for a sidebar, a card, or a
#' tab of a larger app. Pair it with [survey_server()] with the same `id`.
#' The survey starts when the chat first shows on the screen, so a closed
#' sidebar does not start a session.
#'
#' @param id The module id. It must be the same in the UI and the server.
#' @param drawer `FALSE` for no drawer, or a [shinychat::chat_drawer()] for a
#'   panel beside the chat. The `drawer` function of [survey_server()] fills
#'   it with the answers.
#' @param progress Whether to show the progress cue below the chat input.
#' @param placeholder The placeholder text of the chat input.
#' @param icon_assistant The icon next to the survey messages, or `NULL` for
#'   no icon. See [shinychat::chat_ui()].
#' @return A Shiny tag with the chat, the progress cue, and a footer that shows
#'   the closing message.
#' @seealso The `"icecream"` example of [run_example()] puts the chat in
#'   the sidebar of a shop page.
#' @export
#' @examplesIf interactive() && rlang::is_installed("RSQLite")
#' library(shiny)
#' library(bslib)
#'
#' ui <- page_sidebar(
#'   sidebar = sidebar(
#'     survey_chat_ui(
#'       "survey",
#'       drawer = shinychat::chat_drawer(title = "Answers", open = FALSE)
#'     ),
#'     position = "right",
#'     fillable = TRUE,
#'     width = 440
#'   ),
#'   "The main page content"
#' )
survey_chat_ui <- function(
  id,
  drawer = FALSE,
  progress = TRUE,
  placeholder = "Type your answer...",
  icon_assistant = NULL
) {
  ns <- shiny::NS(id)
  check_drawer_config(drawer)
  check_bool(progress)
  check_string(placeholder)
  toolbar <- if (progress || !isFALSE(drawer)) {
    htmltools::div(
      class = "sb-toolbar",
      if (progress) shiny::uiOutput(ns("progress")),
      if (!isFALSE(drawer)) drawer_toggle(ns, drawer$title)
    )
  }
  htmltools::tagList(
    htmltools::singleton(
      htmltools::tags$head(htmltools::tags$style(htmltools::HTML(styles)))
    ),
    shinychat::chat_ui(
      id = ns("chat"),
      class = "sb-chat",
      placeholder = placeholder,
      drawer = drawer,
      footer = htmltools::tagList(
        survey_waiter(ns("waiter")),
        shiny::uiOutput(ns("footer"))
      ),
      toolbar_input = toolbar,
      icon_assistant = icon_assistant,
      enable_cancel = FALSE,
      allow_attachments = FALSE
    )
  )
}

# A labeled button beside the chat input that opens and closes the drawer. It
# shows once the server has put answers in the drawer.
drawer_toggle <- function(ns, title) {
  label <- if (is.null(title) || !nzchar(title)) "Your answers" else title
  htmltools::span(
    `data-display-if` = "output.drawer_ready",
    `data-ns-prefix` = ns(""),
    shiny::actionButton(
      ns("drawer_toggle"),
      label = label,
      icon = shiny::icon("clipboard-list"),
      class = "btn-sm btn-outline-primary rounded-pill"
    )
  )
}

# Overlay that covers the chat and hides its input until the server checks
# the model. The server removes it by `id` when the survey starts or locks.
survey_waiter <- function(id, label = "Connecting...") {
  htmltools::div(
    id = id,
    class = "sb-overlay sb-waiter",
    role = "status",
    htmltools::div(
      class = "spinner-border text-primary",
      `aria-hidden` = "true"
    ),
    htmltools::span(label)
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

# Footer that retires the chat input. "complete" shows a green check below the
# chat after the survey; "locked" covers the whole chat with a red cross and
# the message when the survey cannot start. The chat re-enables its own input
# at the end of each stream, so a style rule hides the input instead of the
# `disabled` property. `chat_id` is the full, namespaced id.
survey_complete <- function(
  message,
  chat_id,
  status = c("complete", "locked")
) {
  status <- rlang::arg_match(status)
  htmltools::tagList(
    htmltools::tags$style(htmltools::HTML(sprintf(
      "#%s shiny-chat-input { display: none; }",
      chat_id
    ))),
    survey_status(message, status)
  )
}

# The closing or locked message with its icon, for the chat footer and the
# form
survey_status <- function(message, status = c("complete", "locked")) {
  status <- rlang::arg_match(status)
  icon <- if (status == "complete") "\u2713" else "\u2715"
  class <- if (status == "complete") "sb-complete" else "sb-overlay sb-locked"
  htmltools::div(
    class = class,
    role = "status",
    htmltools::span(class = "sb-complete-icon", icon),
    htmltools::span(message)
  )
}

# One step of the form: the intro, the input with the question as its
# label, a place for the error, and the Next button. The button is busy
# while the LLM checks typed text, so it cannot submit twice.
form_step <- function(ns, prompt, question) {
  htmltools::tagList(
    form_input(ns, prompt, question),
    shiny::uiOutput(ns("form_error")),
    bslib::input_task_button(
      ns("form_next"),
      "Next",
      label_busy = "Checking..."
    )
  )
}
