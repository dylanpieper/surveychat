# Structured extraction and content generation with ellmer ----

# Each call works on a copy with no history, so one chat object can serve
# every user session and no answer leaks into another prompt.
fresh_chat <- function(chat) {
  chat$clone()$set_turns(list())
}

# Extracts the answer and the `valid` flag from one user reply.
# The question and the earlier answers go into the prompt, so a generic
# `valid` rule has context: a reply can build on what the user said before.
# With `early = TRUE`, the schema also has optional fields for later questions.
extract_response <- function(
  chat,
  question_text,
  user_input,
  schema,
  early = FALSE,
  answers = list(),
  asked = list()
) {
  prompt <- paste0(
    "Extract the answer from this survey reply.\n\n",
    if (length(answers) > 0) {
      paste0(
        answers_so_far(answers, asked),
        "\nThese answers are context only. Extract only from the reply.\n\n"
      )
    },
    "Question: ",
    question_text %||% "",
    "\n",
    "Reply: ",
    user_input,
    if (early) {
      paste0(
        "\n\nThe reply can also answer later questions. Fill a later field ",
        "only when the reply states that answer clearly. Do not guess."
      )
    }
  )
  fresh_chat(chat)$chat_structured(prompt, type = schema)
}

# Generates text from a prompt_llm() with the earlier answers filled in.
# Stops with an error if the LLM returns no text, so the caller can fall back.
# With `context = TRUE`, for the completion message, the prompt also lists
# every answer so far, asks the LLM to use only what the user said, and
# asks no question, since the survey is over.
generate_content <- function(
  chat,
  prompt,
  answers,
  context = FALSE,
  asked = list()
) {
  schema <- ellmer::type_object(
    content = ellmer::type_string("The generated text")
  )
  text <- interpolate(prompt$prompt, answers)
  if (context) {
    text <- paste0(
      text,
      "\n\n",
      answers_so_far(answers, asked),
      "\n\nUse only what these answers say. Do not mention anything that ",
      "they do not say. This is the last message of the survey, so do not ",
      "ask a question."
    )
  }
  result <- fresh_chat(chat)$chat_structured(text, type = schema)
  content <- result[["content"]]
  if (!rlang::is_string(content) || !nzchar(trimws(content))) {
    cli::cli_abort("The LLM returned no text.")
  }
  content
}

# Writes an adaptive question from a prompt_llm() and the answers so far.
# The model can decline: an adaptive question fills a gap, so it is not
# asked when the answers already cover it or no good question fits. Returns
# the question, or NULL to skip. With `allow_skip = FALSE`, the question is
# always asked. Stops with an error if the call fails.
generate_question <- function(
  chat,
  prompt,
  answers,
  allow_skip = TRUE,
  asked = list()
) {
  content <- ellmer::type_string(paste0(
    "The question to ask.",
    if (allow_skip) " Always write it, also when you skip."
  ))
  # The decision comes first, so the question does not lead it
  schema <- if (allow_skip) {
    ellmer::type_object(
      skip = ellmer::type_boolean(
        "TRUE if the answers so far already tell what the question would ask, or no clear, useful question fits. Otherwise FALSE."
      ),
      content = content
    )
  } else {
    ellmer::type_object(content = content)
  }
  result <- fresh_chat(chat)$chat_structured(
    paste0(
      interpolate(prompt$prompt, answers),
      "\n\n",
      answers_so_far(answers, asked),
      "\n\n",
      if (allow_skip) {
        paste0(
          "Set skip to TRUE if these answers already tell what the question ",
          "would ask, or no clear, useful question fits. Always write the ",
          "question. "
        )
      },
      "Ask one open question. Unless the prompt above asks for them, do not ",
      "list example answers or name products or tools that the user did not ",
      "name."
    ),
    type = schema
  )
  content <- result[["content"]]
  if (allow_skip && isTRUE(result[["skip"]])) {
    return(NULL)
  }
  if (!rlang::is_string(content) || !nzchar(trimws(content))) {
    cli::cli_abort("The LLM returned no question.")
  }
  content
}

# The answers as a list for a prompt, one "- question (id): value" line
# each, so the model knows what each answer is about. `asked` holds the
# question text that the user saw, by id; an answer with no text is
# "- id: value".
answers_so_far <- function(answers, asked = list()) {
  if (length(answers) == 0) {
    return("Answers so far: none.")
  }
  lines <- vapply(
    names(answers),
    \(id) {
      text <- asked[[id]]
      label <- if (rlang::is_string(text) && nzchar(text)) {
        paste0(squish(text), " (", id, ")")
      } else {
        id
      }
      paste0("- ", label, ": ", paste(answers[[id]], collapse = ", "))
    },
    character(1)
  )
  paste(c("Answers so far:", lines), collapse = "\n")
}

# Generates answer choices from a prompt_llm() with the earlier answers filled
# in. Returns the unique, non-empty strings; the caller caps them after its
# own filters. Stops with an
# error if there are none, so the caller can show no choices.
generate_choices <- function(chat, prompt, answers) {
  schema <- ellmer::type_object(
    choices = ellmer::type_array(
      ellmer::type_string("One short answer choice, a few words at most")
    )
  )
  result <- fresh_chat(chat)$chat_structured(
    interpolate(prompt$prompt, answers),
    type = schema
  )
  choices <- trimws(as.character(unlist(result[["choices"]])))
  choices <- unique(choices[!is.na(choices) & nzchar(choices)])
  if (length(choices) == 0) {
    cli::cli_abort("The LLM returned no choices.")
  }
  choices
}
