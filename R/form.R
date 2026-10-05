# Form answers ----
#
# The form view takes each answer from a Shiny input. The functions here
# check the type of the answer and tell when it also needs LLM validation.

# Checks a form value against the answer type of `question`. Returns
# `list(ok, value, raw, error)`: `value` has the answer type, `raw` is the
# trimmed text that the database records, and `error` is the message for the
# user when `ok` is FALSE. An empty optional answer is NA, as a skipped answer
# in the chat.
form_value <- function(question, value) {
  type <- question$answer
  if (question_kind(question) == "multi") {
    return(form_multi_value(type, value))
  }
  raw <- form_text(value)
  if (!nzchar(raw)) {
    if (isTRUE(type@required)) {
      return(form_error("Please answer this question."))
    }
    return(form_ok(NA, raw))
  }
  switch(
    question_kind(question),
    date = {
      date <- suppressWarnings(as.Date(raw, format = "%Y-%m-%d"))
      if (is.na(date)) {
        form_error("Enter a date as YYYY-MM-DD.")
      } else {
        form_ok(format(date, "%Y-%m-%d"), format(date, "%Y-%m-%d"))
      }
    },
    enum = if (raw %in% type@values) {
      form_ok(raw, raw)
    } else {
      form_error("Choose one of the options.")
    },
    integer = {
      number <- suppressWarnings(as.numeric(raw))
      whole <- is.finite(number) &&
        number == round(number) &&
        abs(number) <= .Machine$integer.max
      if (!whole) {
        form_error("Enter a whole number.")
      } else {
        form_ok(as.integer(number), raw)
      }
    },
    number = {
      number <- suppressWarnings(as.numeric(raw))
      if (!is.finite(number)) {
        form_error("Enter a number.")
      } else {
        form_ok(number, raw)
      }
    },
    boolean = {
      flag <- as.logical(raw)
      if (is.na(flag)) {
        form_error("Choose yes or no.")
      } else {
        form_ok(flag, raw)
      }
    },
    form_ok(raw, raw)
  )
}

# Whether a form answer needs LLM validation: typed text that is not one of
# the shown choices, or any answer to a question with its own `valid` rule.
# A skipped optional answer needs no check.
form_needs_validation <- function(question, prompt, raw) {
  if (!nzchar(raw)) {
    return(FALSE)
  }
  if (isTRUE(question$own_valid)) {
    return(TRUE)
  }
  question_kind(question) == "string" &&
    !raw %in% c(prompt$generated, prompt$fixed)
}

# A multi-select value from checkboxes: the chosen values, with JSON text as
# `raw`. No choice is a skipped answer if the answer is optional.
form_multi_value <- function(type, value) {
  value <- as.character(unlist(value))
  if (length(value) == 0) {
    if (isTRUE(type@required)) {
      return(form_error("Please choose at least one option."))
    }
    return(form_ok(NA, ""))
  }
  if (!all(value %in% type@items@values)) {
    return(form_error("Choose from the options."))
  }
  form_ok(value, answer_json(value))
}

# The Shiny input for a question prompt, with the text as its label and the
# intro above it. Each question has its own input id, so no value carries
# over from an earlier step.
form_input <- function(ns, prompt, question) {
  id <- ns(form_id(prompt))
  label <- prompt$text
  type <- question$answer
  kind <- question_kind(question)
  picks <- pick_choices(prompt, question)
  input <- if (length(picks) > 0) {
    # One click submits a choice. A string also takes typed text with Next.
    htmltools::tagList(
      htmltools::div(
        class = "form-group shiny-input-container",
        htmltools::tags$label(class = "control-label", label),
        pick_buttons(ns(paste0("form_pick_", prompt$id)), picks)
      ),
      if (kind == "string") shiny::textInput(id, "Or type your own")
    )
  } else {
    switch(
      kind,
      multi = shiny::checkboxGroupInput(id, label, choices = type@items@values),
      date = form_date(id, label),
      integer = shiny::numericInput(id, label, value = NA, step = 1),
      number = shiny::numericInput(id, label, value = NA),
      shiny::textAreaInput(id, label, rows = 3)
    )
  }
  htmltools::tagList(
    if (!is.null(prompt$intro)) {
      htmltools::p(class = "sb-form-intro", prompt$intro)
    },
    input
  )
}

# The reply in the form input of a question prompt, before the type check
form_read <- function(input, prompt) {
  input[[form_id(prompt)]]
}

form_id <- function(prompt) {
  paste0("form_", prompt$id)
}

# A date input that starts empty. Shiny fills in today's date unless the
# initial date is an empty string.
form_date <- function(id, label) {
  htmltools::tagQuery(shiny::dateInput(id, label))$find("input")$addAttrs(
    `data-initial-date` = ""
  )$allTags()
}


# "enum", "multi" for an array of an enum, or the JSON type of a basic
# ellmer type: "string", "integer", "number", or "boolean"
answer_kind <- function(type) {
  if (inherits(type, "ellmer::TypeEnum")) {
    "enum"
  } else if (inherits(type, "ellmer::TypeArray")) {
    "multi"
  } else {
    type@type
  }
}

# An extracted answer in the shape of its question: a multi-select is a
# character vector, and no choice is NA
normalize_answer <- function(question, value) {
  if (question_kind(question) != "multi" || is.null(value)) {
    return(value)
  }
  value <- as.character(unlist(value))
  if (length(value) == 0) NA else value
}

# Whether an extracted answer fits its input: a date is YYYY-MM-DD
answer_fits <- function(question, value) {
  if (question_kind(question) != "date" || !any(!is.na(value))) {
    return(TRUE)
  }
  rlang::is_string(value) &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value) &&
    !is.na(as.Date(value, format = "%Y-%m-%d"))
}

# The answer as the database stores it: a multi-select as JSON text
stored_answer <- function(question, value) {
  if (question_kind(question) == "multi" && any(!is.na(value))) {
    return(answer_json(value))
  }
  value
}

# A multi-select answer as JSON text, such as ["Vegan","Halal"]
answer_json <- function(value) {
  as.character(jsonlite::toJSON(as.character(unlist(value))))
}

# One trimmed string from an input value; "" for no value. A number never
# uses scientific notation, so 100000 is "100000", not "1e+05".
form_text <- function(value) {
  if (length(value) == 0 || is.na(value[[1]])) {
    return("")
  }
  value <- value[[1]]
  if (is.numeric(value)) {
    return(format(value, scientific = FALSE, trim = TRUE, digits = 15))
  }
  trimws(as.character(value))
}

# The reply as the user saw it, for the chat transcript: the label of a
# yes or no choice, or `skipped` for no answer
form_echo <- function(question, value, skipped) {
  if (question_kind(question) == "multi") {
    value <- as.character(unlist(value))
    return(if (length(value) == 0) skipped else paste(value, collapse = ", "))
  }
  raw <- form_text(value)
  if (!nzchar(raw)) {
    return(skipped)
  }
  if (question_kind(question) == "boolean") {
    flag <- as.logical(raw)
    if (!is.na(flag)) {
      return(if (flag) "Yes" else "No")
    }
  }
  raw
}

form_ok <- function(value, raw) {
  list(ok = TRUE, value = value, raw = raw, error = NULL)
}

form_error <- function(message) {
  list(ok = FALSE, value = NULL, raw = NULL, error = message)
}
