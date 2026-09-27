# Template interpolation ----

placeholder_pattern <- "\\{([^}]+)\\}"

# Replaces each {name} in `template` with `data[[name]]`. A missing value
# leaves the bare name, so a template never fails. With `capitalize = TRUE`, a
# value that starts a sentence gets an uppercase first letter.
interpolate <- function(template, data, capitalize = FALSE) {
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
    name <- substr(template, starts[i] + 1, ends[i] - 1)
    value <- data[[name]]
    found <- length(value) > 0
    replacement <- if (found) paste(value, collapse = ", ") else name

    before <- substr(result, 1, starts[i] - 1)
    if (capitalize && found && grepl("(^|[.!?]\\s*)$", before)) {
      replacement <- capitalize_first(replacement)
    }
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
  gsub("[{}]", "", matches)
}

capitalize_first <- function(text) {
  paste0(toupper(substr(text, 1, 1)), substr(text, 2, nchar(text)))
}
