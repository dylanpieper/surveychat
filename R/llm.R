#' Structured extraction and content generation via ellmer

box::use(
  ellmer[type_object, type_string],
  R/utils[interpolate],
)

#' Generate generic schema for content extraction
#' @param field_name Name of the field to extract
#' @return Schema object for structured data
#' @export
create_generic_schema <- \(field_name = "content") {
  schema_list <- list()
  schema_list[[field_name]] <- type_string("Extract the generated content")
  do.call(type_object, schema_list)
}

#' Extract structured response from user input
#' @param chat Chat object
#' @param user_response User's text input
#' @param schema Extraction schema
#' @return Extracted data
#' @export
extract_response <- \(chat, user_response, schema) {
  chat$clone()$set_turns(list())$chat_structured(user_response, type = schema)
}

#' Generate content using templates
#' @param chat Chat object
#' @param template_config Template configuration with prompt, intro (optional)
#' @param context_data Named list of values for template placeholders
#' @return Generated content
#' @export
generate_content <- \(chat, template_config, context_data = list()) {
  prompt <- interpolate(template_config$prompt, context_data)
  schema <- create_generic_schema("content")
  result <- chat$clone()$set_turns(list())$chat_structured(prompt, type = schema)
  result[["content"]]
}
