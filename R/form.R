# Form answers ----
#
# The form view takes each answer from a Shiny input. The functions here
# check the type of the answer and tell when it also needs the LLM check.

# Checks a form value against the answer type of `question`. Returns
# `list(ok, value, raw, error)`: `value` has the answer type, `raw` is the
# trimmed text that the database records, and `error` is the message for the
# user when `ok` is FALSE. An empty optional answer is NA, as a skipped answer
# in the chat.
form_value <- function(question, value) {
  type <- question$answer
  raw <- form_text(value)
  if (!nzchar(raw)) {
    if (isTRUE(type@required)) {
      return(form_error("Please answer this question."))
    }
    return(form_ok(NA, raw))
  }
  switch(
    answer_kind(type),
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

# Whether a form answer needs the LLM check: typed text that is not one of
# the shown choices, or any answer to a question with its own `valid` rule.
# A skipped optional answer needs no check.
form_needs_check <- function(question, prompt, raw) {
  if (!nzchar(raw)) {
    return(FALSE)
  }
  if (isTRUE(question$own_valid)) {
    return(TRUE)
  }
  answer_kind(question$answer) == "string" &&
    !raw %in% c(prompt$generated, prompt$fixed)
}

# The reply of a question with choices: the typed text if there is any, or
# else the chosen card. NULL if there is neither.
form_reply <- function(choice, other) {
  other <- form_text(other)
  if (nzchar(other)) other else choice
}

# The Shiny input for a question prompt, with the text as its label and the
# intro above it. Each question has its own input id, so no value carries
# over from an earlier step.
form_input <- function(ns, prompt, question) {
  id <- ns(form_id(prompt))
  label <- prompt$text
  type <- question$answer
  choices <- c(prompt$generated, prompt$fixed)
  input <- switch(
    answer_kind(type),
    enum = form_choices(id, label, type@values),
    boolean = form_choices(id, label, c(Yes = "TRUE", No = "FALSE")),
    integer = shiny::numericInput(id, label, value = NA, step = 1),
    number = shiny::numericInput(id, label, value = NA),
    if (length(choices) > 0) {
      htmltools::tagList(
        form_choices(id, label, choices),
        shiny::textInput(paste0(id, "_other"), "Or type your own")
      )
    } else {
      shiny::textAreaInput(id, label, rows = 3)
    }
  )
  htmltools::tagList(
    if (!is.null(prompt$intro)) {
      htmltools::p(class = "sb-form-intro", prompt$intro)
    },
    input
  )
}

# The reply in the form inputs of a question prompt, before the type check
form_read <- function(input, prompt, question) {
  id <- form_id(prompt)
  choices <- c(prompt$generated, prompt$fixed)
  if (answer_kind(question$answer) == "string" && length(choices) > 0) {
    return(form_reply(input[[id]], input[[paste0(id, "_other")]]))
  }
  input[[id]]
}

form_id <- function(prompt) {
  paste0("form_", prompt$id)
}

form_choices <- function(id, label, choices) {
  shiny::radioButtons(id, label, choices = choices, selected = character(0))
}

# "enum", or the JSON type of a basic ellmer type: "string", "integer",
# "number", or "boolean"
answer_kind <- function(type) {
  if (inherits(type, "ellmer::TypeEnum")) "enum" else type@type
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
form_echo <- function(question, raw, skipped) {
  if (!nzchar(raw)) {
    return(skipped)
  }
  if (answer_kind(question$answer) == "boolean") {
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
