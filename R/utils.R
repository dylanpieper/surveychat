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

# The chat message of a question prompt: the intro and the text, then the
# `suggested` note when the LLM wrote the choices. The choices themselves
# show in the chat input below the message.
chat_message <- function(prompt, suggested) {
  c(
    paste(c(prompt$intro, prompt$text), collapse = "\n\n"),
    if (length(prompt$generated) > 0) suggested
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

# The text on one line, with each run of white space as one space
squish <- function(text) {
  trimws(gsub("\\s+", " ", text))
}

# The text without its questions: each sentence that ends with "?" is
# dropped, also before a closing quote or bracket. A sentence ends only where
# the next one does not start with a lowercase letter, so "e.g. for" stays
# whole. An abbreviation before a digit, such as "approx. 3", still ends a
# sentence. The white space between the kept sentences, such as a paragraph
# break, stays. "" if every sentence is a question.
drop_questions <- function(text) {
  if (!grepl("?", text, fixed = TRUE)) {
    return(text)
  }
  sentences <- regmatches(
    text,
    gregexpr(
      "(?s).+?(?:[.!?]+[\"')\\]]*(?:\\s+(?=[^\\s\\p{Ll}])|\\s*$)|$)",
      text,
      perl = TRUE
    )
  )[[1]]
  sentences <- sentences[nzchar(sentences)]
  question <- grepl("\\?[\"')\\]]*\\s*$", sentences, perl = TRUE)
  trimws(paste(sentences[!question], collapse = ""))
}
