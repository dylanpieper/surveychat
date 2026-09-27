#' Start a survey spec
#'
#' A survey spec is a plain list with three parts: `questions`, `messages`,
#' and `config`. Start it with `survey_spec()`, then add to it with the pipe
#' verbs [add_question()], [set_messages()], and [set_config()]. Each verb
#' returns the same list with one more part, so `str()` shows the full spec.
#'
#' @param version The version of the question set. The server writes it to
#'   each session in the database.
#' @return A list of class `surveychat_spec` with no questions, the default
#'   messages, and the default config.
#' @seealso [survey_server()] to run the spec.
#' @export
#' @examples
#' survey <- survey_spec(version = "1.0") |>
#'   add_question(
#'     "name",
#'     text = "What's your name?",
#'     answer = ellmer::type_string("The person's first name")
#'   ) |>
#'   add_question(
#'     "color",
#'     text = "Hi {name}! What's your favorite color?",
#'     answer = ellmer::type_string("The color")
#'   )
#' survey
survey_spec <- function(version = "1.0") {
  check_string(version)
  structure(
    list(
      questions = list(),
      messages = default_messages(),
      config = utils::modifyList(default_config(), list(version = version))
    ),
    class = "surveychat_spec"
  )
}

#' Add a question to a survey spec
#'
#' The order of the `add_question()` calls is the order of the survey. The
#' package builds the extraction schema from `answer` and `valid`: one LLM call
#' extracts the answer and checks it. If the answer is not valid, the survey
#' asks again, up to `tries` times (see [set_config()]).
#'
#' @section Placeholders:
#' `text`, the prompts, and the `format` of `intro` can use `{id}` placeholders
#' for the answers to earlier questions. A placeholder that does not name an
#' earlier question gives a warning, because the user would see the raw name.
#'
#' @param spec A survey spec from [survey_spec()].
#' @param id The question id. It is the name of the extracted field and the
#'   `question_id` in the database. It must be a syntactic name.
#' @param text The question as a string, or a [prompt_llm()] for an adaptive
#'   question that the LLM writes from the earlier answers.
#' @param answer An ellmer type, such as [ellmer::type_string()], that
#'   describes the answer to extract.
#' @param valid The condition for a valid answer, written without TRUE or
#'   FALSE, such as `"they mentioned any flavor"`. If `NULL`, the question uses
#'   the default from [set_config()] at the time of this call.
#' @param intro An optional [prompt_llm()] with a `format`. The LLM generates
#'   content that the survey shows before the question.
#' @return `spec` with the question added at the end.
#' @export
#' @examples
#' survey_spec() |>
#'   add_question(
#'     "flavor",
#'     text = "What's your favorite ice cream flavor?",
#'     answer = ellmer::type_string("The ice cream flavor"),
#'     valid = "they mentioned any flavor"
#'   ) |>
#'   add_question(
#'     "why",
#'     text = "What makes {flavor} your favorite?",
#'     intro = prompt_llm(
#'       "Share a short fun fact about {flavor} ice cream.",
#'       format = "Oh, {flavor}! {content}"
#'     ),
#'     answer = ellmer::type_string("The reason they like it")
#'   ) |>
#'   add_question(
#'     "follow_up",
#'     text = prompt_llm(
#'       "The user likes {flavor} because: {why}. Ask one follow-up question."
#'     ),
#'     answer = ellmer::type_string("The answer to the follow-up question")
#'   )
add_question <- function(
  spec,
  id,
  text,
  answer,
  valid = NULL,
  intro = NULL
) {
  check_spec(spec)
  known <- question_ids(spec)
  check_id(id, known)
  if (!rlang::is_string(text)) {
    check_prompt(text)
  }
  if (!inherits(answer, "ellmer::Type")) {
    cli::cli_abort(
      "{.arg answer} must be an ellmer type such as {.fn ellmer::type_string}, not {.obj_type_friendly {answer}}."
    )
  }
  own_valid <- !is.null(valid)
  valid <- valid %||% spec$config$valid
  check_string(valid)
  if (!is.null(intro)) {
    check_prompt(intro)
    if (is.null(intro$format)) {
      cli::cli_abort(
        "{.arg intro} needs a {.arg format} that places {.code {{content}}}."
      )
    }
  }

  question <- list(
    id = id,
    text = text,
    intro = intro,
    valid = valid,
    own_valid = own_valid,
    schema = answer_schema(id, answer, valid)
  )
  where <- paste("Question", id)
  warn_placeholders(question_templates(question), known, where)
  warn_placeholders(intro$format, c(known, "content"), where)

  spec$questions <- c(spec$questions, list(question))
  spec
}

#' Describe text for the LLM to generate
#'
#' Use `prompt_llm()` for `text` in [add_question()] to make an adaptive
#' question, or for `intro` to put generated content before a question.
#'
#' @param prompt The prompt for the LLM. It can use `{id}` placeholders for
#'   the answers to earlier questions.
#' @param format For `intro` only: a template that places the generated text.
#'   It must contain `{content}` and can use `{id}` placeholders. The survey
#'   puts the question after it, with a blank line between.
#' @return A list of class `surveychat_prompt`.
#' @export
#' @examples
#' prompt_llm("Share a short fun fact about {flavor} ice cream.")
#' prompt_llm("Share a fun fact about {flavor}.", format = "Oh! {content}")
prompt_llm <- function(prompt, format = NULL) {
  check_string(prompt)
  if (!is.null(format)) {
    check_string(format)
    if (!"content" %in% extract_variables(format)) {
      cli::cli_abort("{.arg format} must contain {.code {{content}}}.")
    }
  }
  structure(list(prompt = prompt, format = format), class = "surveychat_prompt")
}

#' Set the messages of a survey spec
#'
#' Each argument is optional. The call changes only the messages that it
#' names, and the other messages keep their current values.
#'
#' @param spec A survey spec from [survey_spec()].
#' @param welcome The first message of the survey.
#' @param retry The message when an answer is not valid.
#' @param completion The message after the last answer. It can use `{id}`
#'   placeholders for any answer.
#' @param closed The text that replaces the chat input after the survey.
#' @return `spec` with the new messages.
#' @export
#' @examples
#' survey_spec() |>
#'   set_messages(welcome = "Hi! Three quick questions.")
set_messages <- function(
  spec,
  welcome = NULL,
  retry = NULL,
  completion = NULL,
  closed = NULL
) {
  check_spec(spec)
  given <- compact(list(
    welcome = welcome,
    retry = retry,
    completion = completion,
    closed = closed
  ))
  for (name in names(given)) {
    check_string(given[[name]], arg = name)
  }
  spec$messages <- utils::modifyList(spec$messages, given)
  spec
}

#' Set the config of a survey spec
#'
#' Each argument is optional. The call changes only the values that it names.
#'
#' @param spec A survey spec from [survey_spec()].
#' @param tries The maximum number of retries for an answer that is not valid.
#'   After the last retry, the survey keeps the answer and continues.
#' @param response_delay The delay in seconds before the bot starts a message.
#' @param character_delay The delay in seconds between characters of the
#'   simulated typing. Use `0` for no delay.
#' @param delay_variance The random variation in seconds of `character_delay`.
#' @param version The version of the question set.
#' @param valid The default condition for a valid answer. It applies to each
#'   [add_question()] call after this one that has no `valid` of its own.
#' @return `spec` with the new config.
#' @export
#' @examples
#' survey_spec() |>
#'   set_config(tries = 3, character_delay = 0)
set_config <- function(
  spec,
  tries = NULL,
  response_delay = NULL,
  character_delay = NULL,
  delay_variance = NULL,
  version = NULL,
  valid = NULL
) {
  check_spec(spec)
  if (!is.null(tries)) {
    check_number(tries, whole = TRUE)
  }
  if (!is.null(response_delay)) {
    check_number(response_delay)
  }
  if (!is.null(character_delay)) {
    check_number(character_delay)
  }
  if (!is.null(delay_variance)) {
    check_number(delay_variance)
  }
  if (!is.null(version)) {
    check_string(version)
  }
  if (!is.null(valid)) {
    check_string(valid)
  }

  given <- compact(list(
    tries = tries,
    response_delay = response_delay,
    character_delay = character_delay,
    delay_variance = delay_variance,
    version = version,
    valid = valid
  ))
  spec$config <- utils::modifyList(spec$config, given)
  spec
}

#' @export
print.surveychat_spec <- function(x, ...) {
  n <- length(x$questions)
  cli::cat_line(cli::format_inline(
    "<surveychat_spec> version {.val {x$config$version}}, {n} question{?s}"
  ))
  for (i in seq_len(n)) {
    question <- x$questions[[i]]
    tags <- c(
      if (is_adaptive(question)) "adaptive",
      if (!is.null(question$intro)) "intro",
      if (question$own_valid) "own rule"
    )
    tags <- if (length(tags)) paste0(" [", paste(tags, collapse = ", "), "]")
    cli::cat_line(sprintf("%d. %s%s", i, question$id, tags %||% ""))
  }
  invisible(x)
}

# Checks run once, when the server starts ----

validate_spec <- function(spec, call = rlang::caller_env()) {
  check_spec(spec, call = call)
  if (length(spec$questions) == 0) {
    cli::cli_abort(
      c(
        "The survey has no questions.",
        "i" = "Add one with {.fn add_question}."
      ),
      call = call
    )
  }
  first <- spec$questions[[1]]
  if (is_adaptive(first)) {
    cli::cli_abort(
      c(
        "The first question {.val {first$id}} cannot be adaptive.",
        "i" = "There are no earlier answers for its prompt to use."
      ),
      call = call
    )
  }
  warn_placeholders(
    spec$messages$completion,
    question_ids(spec),
    "The completion message"
  )
  invisible(spec)
}

# Helpers ----

default_messages <- function() {
  list(
    welcome = "Hello! Thanks for taking this survey.",
    retry = "Sorry, I didn't quite get that. Could you try again?",
    completion = "Thank you! Your answers are recorded.",
    closed = "Survey complete. Thank you!"
  )
}

default_config <- function() {
  list(
    tries = 2,
    response_delay = 0,
    character_delay = 0.02,
    delay_variance = 0.01,
    version = "1.0",
    valid = paste(
      "the reply answers the question, even if it is brief, informal, or",
      "unconventional, and it is not off-topic, rude, or nonsense"
    )
  )
}

reserved_ids <- c("valid", "content")

check_id <- function(id, known, call = rlang::caller_env()) {
  check_string(id, call = call)
  if (make.names(id) != id) {
    cli::cli_abort(
      "{.arg id} must be a syntactic name, not {.val {id}}.",
      call = call
    )
  }
  if (id %in% reserved_ids) {
    cli::cli_abort(
      "{.arg id} cannot be {.val {id}}; the package uses that name.",
      call = call
    )
  }
  if (id %in% known) {
    cli::cli_abort(
      "The spec already has a question with id {.val {id}}.",
      call = call
    )
  }
  invisible(id)
}

# The author writes `valid` as a condition; the flag description turns it into
# the TRUE/FALSE instruction for the LLM
answer_schema <- function(id, answer, valid) {
  rule <- paste0(
    "TRUE if the reply is valid: ",
    sub("[.[:space:]]+$", "", valid),
    ". Otherwise FALSE."
  )
  fields <- list(answer, ellmer::type_boolean(rule))
  names(fields) <- c(id, "valid")
  do.call(ellmer::type_object, fields)
}

question_ids <- function(spec) {
  vapply(spec$questions, \(question) question$id, character(1))
}

is_adaptive <- function(question) {
  inherits(question$text, "surveychat_prompt")
}

question_templates <- function(question) {
  c(
    if (is_adaptive(question)) question$text$prompt else question$text,
    question$intro$prompt
  )
}

warn_placeholders <- function(templates, known, where) {
  used <- unique(unlist(lapply(templates, extract_variables)))
  unknown <- setdiff(used, known)
  if (length(unknown)) {
    placeholders <- paste0("{", unknown, "}")
    cli::cli_warn(c(
      "{where} uses {cli::qty(unknown)}placeholder{?s} {.code {placeholders}} that {?does/do} not name an earlier question.",
      "i" = "The user will see the raw name. Check the spelling and the order of the questions."
    ))
  }
  invisible(unknown)
}

compact <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}
