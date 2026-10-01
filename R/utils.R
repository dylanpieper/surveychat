# Template interpolation ----

placeholder_pattern <- "\\{([^}]+)\\}"

# Replaces each {name} in `template` with `data[[name]]`. A missing value (such
# as a skipped answer) uses the fallback of {name|fallback}, or else leaves the
# bare name, so a template never fails. With `capitalize = TRUE`, a value that
# starts a sentence gets an uppercase first letter. `escape` changes each
# replacement last, such as escape_markdown() for text that is rendered.
interpolate <- function(
  template,
  data,
  capitalize = FALSE,
  escape = identity
) {
  if (is.null(template)) {
    return(template)
  }
  matches <- gregexpr(placeholder_pattern, template)[[1]]
  if (matches[1] == -1) {
    return(template)
  }

  starts <- as.integer(matches)
  ends <- starts + attr(matches, "match.length") - 1
  result <- template

  # Right to left, so earlier positions stay valid after each replacement
  for (i in rev(seq_along(starts))) {
    placeholder <- parse_placeholder(
      substr(template, starts[i] + 1, ends[i] - 1)
    )
    value <- data[[placeholder$name]]
    value <- value[!is.na(value)]
    found <- length(value) > 0
    replacement <- if (found) {
      paste(value, collapse = ", ")
    } else {
      placeholder$fallback %||% placeholder$name
    }
    filled <- found || !is.null(placeholder$fallback)

    before <- substr(result, 1, starts[i] - 1)
    if (capitalize && filled && grepl("(^|[.!?]\\s*)$", before)) {
      replacement <- capitalize_first(replacement)
    }
    replacement <- escape(replacement)
    result <- paste0(
      before,
      replacement,
      substr(result, ends[i] + 1, nchar(result))
    )
  }

  result
}

# The names of the {placeholders} in a template, in order of use
extract_variables <- function(template) {
  if (is.null(template)) {
    return(character(0))
  }
  matches <- regmatches(template, gregexpr(placeholder_pattern, template))[[1]]
  vapply(
    gsub("[{}]", "", matches),
    \(inner) parse_placeholder(inner)$name,
    character(1),
    USE.NAMES = FALSE
  )
}

# Splits "name|fallback" into its parts. `fallback` is NULL if there is no bar.
parse_placeholder <- function(inner) {
  bar <- regexpr("|", inner, fixed = TRUE)
  if (bar == -1) {
    return(list(name = trimws(inner), fallback = NULL))
  }
  list(
    name = trimws(substr(inner, 1, bar - 1)),
    fallback = substr(inner, bar + 1, nchar(inner))
  )
}

# Markdown for a grid of shinychat suggestion cards, one for each choice. A
# click sends the choice as the reply. NULL for no choices.
suggestion_cards <- function(choices) {
  if (length(choices) == 0) {
    return(NULL)
  }
  spans <- sprintf(
    '* <span class="suggestion">%s</span>',
    htmltools::htmlEscape(choices)
  )
  paste(spans, collapse = "\n")
}

# The chat message of a question prompt: the intro and the text, then the
# choice cards if there are any. Generated choices come after the
# `suggested` note, which tells the user that they are from the LLM; the
# fixed choices follow in their own list, so they always show.
chat_message <- function(prompt, suggested) {
  ideas <- if (length(prompt$generated) > 0) {
    paste0(suggested, "\n\n", suggestion_cards(prompt$generated))
  }
  cards <- c(ideas, suggestion_cards(prompt$fixed))
  c(
    paste(c(prompt$intro, prompt$text), collapse = "\n\n"),
    if (length(cards) > 0) paste(cards, collapse = "\n\n")
  )
}

# Backslash-escapes each ASCII punctuation mark, so commonmark shows the text
# as typed: no HTML, links, or emphasis from user input
escape_markdown <- function(text) {
  gsub("([!-/:-@\\[-`{-~])", "\\\\\\1", text, perl = TRUE)
}

# A message template as safe HTML: the template is markdown, and each answer
# in it is escaped
render_message <- function(template, answers) {
  shiny::markdown(
    interpolate(template, answers, capitalize = TRUE, escape = escape_markdown)
  )
}

capitalize_first <- function(text) {
  paste0(toupper(substr(text, 1, 1)), substr(text, 2, nchar(text)))
}
