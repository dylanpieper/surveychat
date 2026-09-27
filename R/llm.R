# Structured extraction and content generation with ellmer ----

# Each call works on a copy with no history, so one chat object can serve
# every user session and no answer leaks into another prompt.
fresh_chat <- function(chat) {
  chat$clone()$set_turns(list())
}

# Extracts the answer and the `valid` flag from one user reply.
# The question goes into the prompt, so a generic `valid` rule has context.
extract_response <- function(chat, question_text, user_input, schema) {
  prompt <- paste0(
    "Extract the answer from this survey reply.\n\n",
    "Question: ",
    question_text %||% "",
    "\n",
    "Reply: ",
    user_input
  )
  fresh_chat(chat)$chat_structured(prompt, type = schema)
}

# Generates text from a prompt_llm() with the earlier answers filled in.
# Stops with an error if the LLM returns no text, so the caller can fall back.
generate_content <- function(chat, prompt, answers) {
  schema <- ellmer::type_object(
    content = ellmer::type_string("The generated text")
  )
  result <- fresh_chat(chat)$chat_structured(
    interpolate(prompt$prompt, answers),
    type = schema
  )
  content <- result[["content"]]
  if (!rlang::is_string(content) || !nzchar(trimws(content))) {
    cli::cli_abort("The LLM returned no text.")
  }
  content
}
