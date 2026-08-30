#' Template interpolation and text helpers

#' Capitalize first letter of a string
#' @param text String to capitalize
#' @return String with first letter capitalized
#' @export
capitalize_first <- \(text) {
  if (is.null(text) || nchar(text) == 0) {
    return(text)
  }
  paste0(toupper(substr(text, 1, 1)), substr(text, 2, nchar(text)))
}

#' String interpolation with context-aware capitalization
#' @param template String with {variable} placeholders
#' @param data Named list or environment with variable values
#' @param fallback_value Value to use for missing variables (default: variable name)
#' @return Interpolated string with proper capitalization
#' @export
interpolate_with_context <- \(template, data, fallback_value = NULL) {
  result <- template
  if (is.null(template)) {
    return(template)
  }

  # Extract all {variable} patterns
  matches <- gregexpr("\\{([^}]+)\\}", template)[[1]]
  if (matches[1] == -1) {
    return(template)
  }

  # Process matches in reverse order to preserve positions
  match_starts <- as.numeric(matches)
  match_lengths <- attr(matches, "match.length")

  for (i in length(match_starts):1) {
    start <- match_starts[i]
    length <- match_lengths[i]

    # Extract variable name
    var_text <- substr(template, start, start + length - 1)
    var_name <- gsub("\\{|\\}", "", var_text)

    # Get replacement value
    replacement <- if (!is.null(data[[var_name]])) {
      as.character(data[[var_name]])
    } else if (!is.null(fallback_value)) {
      as.character(fallback_value)
    } else {
      var_name
    }

    # Check if variable starts a sentence (at beginning or after ". ", "! ", "? ")
    is_sentence_start <- start == 1 ||
      grepl("[\\.\\!\\?]\\s*$", substr(result, 1, start - 1))

    # Capitalize if at sentence start
    if (is_sentence_start && !is.null(data[[var_name]])) {
      replacement <- capitalize_first(replacement)
    }

    # Replace in template
    result <- paste0(
      substr(result, 1, start - 1),
      replacement,
      substr(result, start + length, nchar(result))
    )
  }

  result
}

#' String interpolation with named placeholders
#' @param template String with {variable} placeholders
#' @param data Named list or environment with variable values
#' @param fallback_value Value to use for missing variables (default: variable name)
#' @return Interpolated string
#' @export
interpolate <- \(template, data, fallback_value = NULL) {
  result <- template
  if (is.null(template)) {
    return(template)
  }

  # Extract all {variable} patterns
  matches <- gregexpr("\\{([^}]+)\\}", template)[[1]]
  if (matches[1] == -1) {
    return(template)
  }

  # Process matches in reverse order to preserve positions
  match_starts <- as.numeric(matches)
  match_lengths <- attr(matches, "match.length")

  for (i in length(match_starts):1) {
    start <- match_starts[i]
    length <- match_lengths[i]

    # Extract variable name
    var_text <- substr(template, start, start + length - 1)
    var_name <- gsub("\\{|\\}", "", var_text)

    # Get replacement value
    replacement <- if (!is.null(data[[var_name]])) {
      as.character(data[[var_name]])
    } else if (!is.null(fallback_value)) {
      as.character(fallback_value)
    } else {
      var_name
    }

    # Replace in template
    result <- paste0(
      substr(result, 1, start - 1),
      replacement,
      substr(result, start + length, nchar(result))
    )
  }

  result
}

#' Extract variable names from template strings
#' @param template Template string with {variable} placeholders
#' @return Character vector of variable names
#' @export
extract_variables <- \(template) {
  if (is.null(template)) {
    return(character(0))
  }

  matches <- regmatches(template, gregexpr("\\{([^}]+)\\}", template))[[1]]
  if (length(matches) == 0) {
    return(character(0))
  }

  # Extract variable names without braces
  gsub("\\{|\\}", "", matches)
}

#' Personalize question text with user responses
#' @param text Question text with {placeholders}
#' @param responses List of response values
#' @return Personalized text
#' @export
personalize_text <- \(text, responses) {
  if (is.null(text)) {
    return(text)
  }

  # Filter out internal fields
  filtered_responses <- responses[!names(responses) %in% c(
    "adaptive_question_text", "adaptive_question_response", "answered_clearly"
  )]

  interpolate_with_context(text, filtered_responses)
}
