# Live checks of model behavior that the unit tests script with fake_chat().
# They call Claude Haiku and skip without ANTHROPIC_API_KEY. Run them with
# tests/live/run.R; R CMD check and CI do not run this folder.

live_model <- "anthropic/claude-haiku-4-5"

live_chat <- function() {
  testthat::skip_if(
    !nzchar(Sys.getenv("ANTHROPIC_API_KEY")),
    "ANTHROPIC_API_KEY is not set"
  )
  ellmer::chat(live_model, echo = "none")
}

# Extracts one reply to the first question of `spec`, with the other
# questions as later questions that the reply can answer early
extract_live <- function(chat, spec, reply) {
  question <- spec$questions[[1]]
  later <- spec$questions[-1]
  extract_response(
    chat,
    question$text,
    reply,
    extraction_schema(question, later, list()),
    early = length(later) > 0
  )
}

test_that("a vague reply to a yes or no question is not valid", {
  chat <- live_chat()
  spec <- survey_spec() |>
    add_question(
      "dinner",
      text = "Will you join us for dinner after the workshop?",
      answer = ellmer::type_boolean("Whether they join the dinner")
    )

  for (reply in c("maybe", "not sure yet, depends on my train")) {
    result <- extract_live(chat, spec, reply)
    expect_false(isTRUE(result$valid), label = reply)
  }
  clear <- extract_live(chat, spec, "yeah, count me in")
  expect_true(isTRUE(clear$valid))
  expect_true(isTRUE(clear$dinner))
})

test_that("a date reply becomes an ISO date, also a relative one", {
  chat <- live_chat()
  # Saturday, October 3, 2026
  local_mocked_bindings(
    now = function() as.POSIXct("2026-10-03 12:00:00"),
    .package = "surveychat"
  )
  spec <- survey_spec() |>
    add_question(
      "day",
      text = "Which day suits you?",
      answer = ellmer::type_string("The day"),
      input = "date"
    )

  expect_equal(extract_live(chat, spec, "May 4, 1990")$day, "1990-05-04")
  expect_equal(extract_live(chat, spec, "tomorrow")$day, "2026-10-04")
  # "Next Friday" can mean this coming Friday or the one after it
  expect_true(
    extract_live(chat, spec, "next Friday")$day %in%
      c("2026-10-09", "2026-10-16")
  )
  # A reply that names no day is not valid
  expect_false(isTRUE(extract_live(chat, spec, "sometime soon")$valid))
})

test_that("a free reply maps to an enum value", {
  chat <- live_chat()
  spec <- survey_spec() |>
    add_question(
      "role",
      text = "What is your role?",
      answer = ellmer::type_enum(
        c("Student", "Researcher", "Analyst", "Developer", "Engineer", "Other"),
        "Their main role at work or school"
      )
    )

  expect_equal(extract_live(chat, spec, "I'm a grad student")$role, "Student")
})

test_that("one reply answers a later question early", {
  chat <- live_chat()
  spec <- survey_spec() |>
    add_question(
      "name",
      text = "What's your name?",
      answer = ellmer::type_string("The first name")
    ) |>
    add_question(
      "served",
      text = "How do you like your ice cream served?",
      answer = ellmer::type_enum(c("Cone", "Cup", "Sundae"), "How it is served")
    )

  result <- extract_live(chat, spec, "I'm Ana, and I always get a cone")
  expect_equal(result$name, "Ana")
  expect_equal(result$served, "Cone")
})

test_that("a reply that breaks the rule gets a hint", {
  chat <- live_chat()
  spec <- survey_spec() |>
    add_question(
      "goal",
      text = "What do you hope to learn at the workshop?",
      answer = ellmer::type_string("The topic or skill"),
      valid = "they named a topic or skill"
    )

  result <- extract_live(chat, spec, "asdf")
  expect_false(isTRUE(result$valid))
  expect_true(nzchar(trimws(result$retry_hint %||% "")))
})

# The survey spec of the workshop example, from its app.R
workshop_survey <- function(env = parent.frame()) {
  app <- readLines(test_path(
    "..",
    "..",
    "inst",
    "examples",
    "panel-chat-form",
    "app.R"
  ))
  start <- grep("^# Survey ----$", app)
  end <- grep("^# Backends ----$", app)
  stopifnot(length(start) == 1, length(end) == 1)
  code <- app[seq(start, end - 1)]
  spec_env <- new.env()
  # The example code calls ellmer types by their short names
  suppressWarnings(withr::local_package("ellmer", .local_envir = env))
  eval(parse(text = code), envir = spec_env)
  spec_env$survey
}

word_count <- function(text) {
  length(strsplit(trimws(text), "\\s+")[[1]])
}

test_that("the workshop closing line is one short reply with no thanks", {
  chat <- live_chat()
  survey <- workshop_survey()
  # The answers in the README GIF
  answers <- list(
    name = "Dylan",
    role = "Software Engineer",
    goal = "New AI coding skills",
    experience = "I use Claude Code",
    project = "I want to create an R package called surveychat",
    project_detail = "Users can fill out forms using natural language"
  )

  completion <- survey$messages$completion
  line <- generate_content(chat, completion, answers, context = TRUE)
  expect_lte(word_count(line), 30)
  expect_no_match(line, "thank", ignore.case = TRUE)
  expect_no_match(line, "?", fixed = TRUE)

  # With no project answers, the line does not invent a project
  answers$project <- NULL
  answers$project_detail <- NULL
  line <- generate_content(chat, completion, answers, context = TRUE)
  expect_no_match(
    line,
    "\\b(app|project|package|surveychat)\\b",
    ignore.case = TRUE
  )
})

test_that("the workshop intro is short, asks nothing, and does not read a skip as silence", {
  chat <- live_chat()
  intro <- Filter(\(q) q$id == "project", workshop_survey()$questions)[[
    1
  ]]$intro
  answers <- list(
    name = "Dylan",
    role = "Software Engineer",
    goal = "New AI coding skills"
  )

  given <- generate_content(
    chat,
    intro,
    c(answers, experience = "I use Claude Code")
  )
  missing <- generate_content(chat, intro, answers)
  for (line in c(given, missing)) {
    expect_lte(word_count(line), 18)
    expect_no_match(line, "?", fixed = TRUE)
  }
  # A skipped experience question is not mentioned or read as a user who said nothing
  expect_no_match(
    missing,
    "haven't|have not|didn't|did not|not shared|unknown|experience",
    ignore.case = TRUE
  )
})

test_that("an adaptive question does not lead unless the prompt asks", {
  chat <- live_chat()
  experience <- Filter(
    \(q) q$id == "experience",
    workshop_survey()$questions
  )[[1]]$text
  answers <- list(role = "Student", goal = "how to use AI to code")

  open <- generate_question(chat, experience, answers, allow_skip = FALSE)
  expect_no_match(
    open,
    "such as|e\\.g\\.|for example|ChatGPT|Copilot|Cursor|Claude",
    ignore.case = TRUE
  )
  expect_equal(lengths(regmatches(open, gregexpr("?", open, fixed = TRUE))), 1)

  # The author's prompt can ask for options
  options <- generate_question(
    chat,
    prompt_llm("Ask which of R, Python, or SQL this {role} uses most."),
    answers,
    allow_skip = FALSE
  )
  expect_match(options, "Python", fixed = TRUE)
})

test_that("an adaptive question fills a gap and is skipped when there is none", {
  chat <- live_chat()
  prompt <- prompt_llm(
    "Ask one short question about what {name} hopes to learn at the workshop."
  )

  covered <- generate_question(
    chat,
    prompt,
    list(name = "Ana", goal = "how to build Shiny apps that call LLMs")
  )
  expect_null(covered)

  open <- generate_question(chat, prompt, list(name = "Ana", role = "Student"))
  expect_true(rlang::is_string(open) && nzchar(open))
})

test_that("a reply that builds on an earlier answer is valid", {
  chat <- live_chat()
  spec <- survey_spec() |>
    add_question(
      "detail",
      text = "What kind of R package are you thinking of building, such as one for data analysis or visualization?",
      answer = ellmer::type_string("Their answer to the follow-up question")
    )
  question <- spec$questions[[1]]
  answers <- list(project = "I want to make an R package")

  for (k in 1:3) {
    result <- extract_response(
      chat,
      question$text,
      "I want to make a chatbot survey",
      question$schema,
      answers = answers
    )
    expect_true(isTRUE(result$valid))
  }
  off <- extract_response(
    chat,
    question$text,
    "huh?",
    question$schema,
    answers = answers
  )
  expect_false(isTRUE(off$valid))
})
