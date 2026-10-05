responses_of <- function(con) {
  DBI::dbGetQuery(
    con,
    "SELECT question_id, question_text, answer_extracted, retry_attempt
     FROM responses ORDER BY response_id"
  )
}

test_that("a survey runs from welcome to completion", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why mint, Ana?"),
    list(why = "fresh", valid = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, con)

  expect_equal(engine$start(), test_spec()$messages$welcome)
  expect_equal(engine$first_question(), "Name?")
  expect_equal(
    engine$process_input("I'm Ana")$message,
    "Hi ana! Ana is a nice name.\n\nAna, flavor?"
  )
  expect_equal(engine$progress(), list(current = 2, total = 3))
  expect_equal(engine$process_input("mint")$message, "Why mint, Ana?")
  expect_equal(
    engine$process_input("fresh")[c("message", "complete")],
    list(message = "Bye ana", complete = TRUE)
  )

  expect_equal(
    responses_of(con)$question_text,
    c("Name?", "Ana, flavor?", "Why mint, Ana?")
  )
  expect_equal(
    DBI::dbGetQuery(con, "SELECT completed FROM sessions")$completed,
    1
  )
  expect_equal(
    engine$answers_so_far(),
    list(name = "ana", flavor = "mint", why = "fresh")
  )
})

choice_spec <- function(choices = NULL, answer = ellmer::type_string("Serve")) {
  survey_spec() |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("Name")
    ) |>
    add_question(
      "serve",
      text = "Cone or cup, {name}?",
      answer = answer,
      choices = choices
    )
}

test_that("an enum question keeps its values for the chat input, not cards", {
  con <- local_sqlite()
  spec <- choice_spec(answer = ellmer::type_enum(c("cone", "cup"), "Serve"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(serve = "cone", valid = TRUE)
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("Ana")$message, "Cone or cup, Ana?")
  expect_equal(engine$current_prompt()$fixed, c("cone", "cup"))
  engine$process_input("cone")
  expect_equal(responses_of(con)$question_text[2], "Cone or cup, Ana?")
})

test_that("a reply that answers a later question skips it and records it", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE, flavor = "mint"),
    list(content = "Why mint, Ana?")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  result <- engine$process_input("I'm Ana and I love mint")
  expect_equal(result$message, "Why mint, Ana?")
  expect_equal(engine$answers_so_far(), list(name = "Ana", flavor = "mint"))
  expect_equal(engine$progress()$current, 3)

  # The adaptive question is not offered as an early field
  expect_named(
    chat$log$types[[1]]@properties,
    c("name", "valid", "retry_hint", "flavor")
  )
  expect_false(chat$log$types[[1]]@properties$flavor@required)
  expect_match(chat$log$prompts[1], "later questions", fixed = TRUE)

  responses <- DBI::dbGetQuery(
    con,
    "SELECT question_id, question_order, question_text, answer_raw,
       answer_extracted, valid FROM responses ORDER BY response_id"
  )
  expect_equal(responses$question_id, c("name", "flavor"))
  expect_equal(responses$question_order, c(1, 2))
  expect_equal(responses$question_text, c("Name?", NA))
  expect_equal(responses$answer_raw, rep("I'm Ana and I love mint", 2))
  expect_equal(responses$answer_extracted, c("Ana", "mint"))
  expect_equal(as.logical(responses$valid), c(TRUE, TRUE))
})

test_that("early answers are ignored while the reply is not valid", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE, flavor = "mint"),
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("?? mint")$message,
    test_spec()$messages$retry
  )
  expect_equal(engine$answers_so_far(), list())
  message <- engine$process_input("Ana")$message
  expect_match(message[1], "Ana, flavor?", fixed = TRUE)
})

test_that("a reply kept after the last retry gives no early answers", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE, flavor = "mint"),
    list(name = "??", valid = FALSE, flavor = "mint"),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  engine$process_input("?? mint")
  message <- engine$process_input("?? mint")$message
  expect_match(message[1], "??, flavor?", fixed = TRUE)
  expect_equal(engine$answers_so_far(), list(name = "??"))
  expect_equal(
    DBI::dbGetQuery(con, "SELECT question_id FROM responses")$question_id,
    c("name", "name")
  )
})

test_that("skip_answered = FALSE asks every question", {
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE, flavor = "mint"),
    list(content = "x")
  )
  spec <- test_spec() |> set_config(skip_answered = FALSE)
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  message <- engine$process_input("Ana, mint")$message
  expect_match(message[1], "Ana, flavor?", fixed = TRUE)
  expect_named(chat$log$types[[1]]@properties, c("name", "valid", "retry_hint"))
  expect_no_match(chat$log$prompts[1], "later questions", fixed = TRUE)
  expect_equal(engine$answers_so_far(), list(name = "Ana"))
})

test_that("a skipped optional answer uses the fallback and stores no value", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("Name", required = FALSE)
    ) |>
    add_question(
      "flavor",
      text = "Hey {name|there}, flavor?",
      answer = ellmer::type_string("Flavor")
    )
  chat <- fake_chat(list(name = NA_character_, valid = TRUE))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("I'd rather not say")$message,
    "Hey there, flavor?"
  )
  expect_equal(engine$answers_so_far(), list())
  expect_true(is.na(responses_of(con)$answer_extracted))
})

test_that("preset choices go to the chat input on any answer type", {
  spec <- choice_spec(choices = c("cone", "cup"))
  engine <- SurveySession$new(
    spec,
    fake_chat(list(name = "Ana", valid = TRUE)),
    local_sqlite()
  )
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("Ana")$message, "Cone or cup, Ana?")
  expect_equal(engine$current_prompt()$fixed, c("cone", "cup"))
})

test_that("generated choices come with the suggested note", {
  spec <- choice_spec(choices = prompt_llm("Serving ideas for {name}"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(choices = c("Cone", " cup ", "Cone", ""))
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("Ana")$message,
    c("Cone or cup, Ana?", spec$messages$suggested)
  )
  expect_equal(engine$current_prompt()$generated, c("Cone", "cup"))
  expect_match(chat$log$prompts[2], "Serving ideas for Ana", fixed = TRUE)
})

test_that("a failed choice generation shows the question with no cards", {
  spec <- choice_spec(choices = prompt_llm("Serving ideas for {name}"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    simpleError("API down")
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  expect_snapshot(message <- engine$process_input("Ana")$message)
  expect_equal(message, "Cone or cup, Ana?")
})

test_that("fixed choices always come after the generated ones", {
  run <- function(generation) {
    spec <- choice_spec(choices = list(prompt_llm("Ideas for {name}"), "Plain"))
    chat <- fake_chat(list(name = "Ana", valid = TRUE), generation)
    engine <- SurveySession$new(spec, chat, local_sqlite())
    engine$start()
    engine$first_question()
    suppressWarnings(engine$process_input("Ana"))
    prompt <- engine$current_prompt()
    c(prompt$generated, prompt$fixed)
  }

  # A generated choice that repeats a fixed one is dropped
  expect_equal(run(list(choices = c("Cone", "plain"))), c("Cone", "Plain"))
  expect_equal(run(simpleError("API down")), "Plain")
})

test_that("the extraction prompt includes the question", {
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, local_sqlite())
  engine$start()
  engine$first_question()
  engine$process_input("I'm Ana")

  expect_match(
    chat$log$prompts[[1]],
    "Question: Name?\nReply: I'm Ana",
    fixed = TRUE
  )
})

test_that("an invalid answer is asked again up to `tries` times", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE),
    list(name = "??", valid = NULL),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  retry <- engine$process_input("?")$message
  moved_on <- engine$process_input("?")$message

  expect_equal(retry, test_spec()$messages$retry)
  expect_match(moved_on, "flavor")

  expect_equal(responses_of(con)$retry_attempt, c(0, 1))
  expect_equal(DBI::dbGetQuery(con, "SELECT retry_count FROM sessions")[[1]], 1)
})

test_that("a failed intro shows the question alone", {
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    simpleError("API down")
  )
  engine <- SurveySession$new(test_spec(), chat, local_sqlite())
  engine$start()
  engine$first_question()

  expect_snapshot(message <- engine$process_input("Ana")$message)
  expect_equal(message, "Ana, flavor?")
})

test_that("a failed adaptive question is skipped", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x"),
    list(flavor = "mint", valid = TRUE),
    list(content = "   ")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  expect_snapshot(result <- engine$process_input("mint"))
  expect_equal(
    result[c("message", "complete")],
    list(message = "Bye Ana", complete = TRUE)
  )
})

test_that("a failed extraction asks again and does not count as a retry", {
  con <- local_sqlite()
  chat <- fake_chat(
    simpleError("rate limited"),
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  expect_snapshot(failed <- engine$process_input("Ana"))
  moved_on <- engine$process_input("Ana")$message

  expect_equal(
    failed,
    list(message = test_spec()$messages$retry, complete = FALSE)
  )
  expect_match(moved_on, "flavor")
  expect_equal(responses_of(con)$retry_attempt, 0)
})

test_that("a failed bookkeeping write does not stop or repeat the survey", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x"),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why mint?"),
    list(why = "fresh", valid = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  local_mocked_bindings(
    update_session_duration = \(...) stop("database busy"),
    complete_session = \(...) stop("database busy")
  )

  expect_snapshot({
    invisible(engine$process_input("Ana"))
    invisible(engine$process_input("mint"))
    last <- engine$process_input("fresh")
  })
  after <- engine$process_input("again")

  expect_equal(
    last[c("message", "complete")],
    list(message = "Bye Ana", complete = TRUE)
  )
  expect_null(after$message)
  expect_equal(responses_of(con)$question_id, c("name", "flavor", "why"))
})

test_that("a failed retry count still asks again and counts the retry", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE),
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  local_mocked_bindings(increment_retry = \(...) stop("database busy"))

  expect_snapshot(retry <- engine$process_input("?"))
  moved_on <- engine$process_input("Ana")$message

  expect_equal(retry$message, test_spec()$messages$retry)
  expect_match(moved_on, "flavor")
  expect_equal(responses_of(con)$retry_attempt, c(0, 1))
})

responses_of_valid <- function(con) {
  DBI::dbGetQuery(con, "SELECT valid FROM responses ORDER BY response_id")$valid
}

test_that("a session can mix form and chat answers and records each method", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why mint, Ana?"),
    list(why = "fresh taste", valid = TRUE)
  )
  spec <- set_config(test_spec(), views = c("chat", "form"))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()
  expect_equal(
    DBI::dbGetQuery(con, "SELECT methods FROM sessions")$methods,
    "chat,form"
  )

  expect_equal(
    engine$submit_form("  ana ")$message,
    "Hi Ana! Ana is a nice name.\n\nAna, flavor?"
  )
  expect_equal(engine$process_input("mint")$message, "Why mint, Ana?")
  expect_equal(
    engine$submit_form("it is fresh")[c("message", "complete")],
    list(message = "Bye Ana", complete = TRUE)
  )

  # Typed form text goes through the same extraction as the chat
  expect_match(chat$log$prompts[1], "Question: Name?\nReply: ana", fixed = TRUE)
  expect_named(chat$log$types[[1]]@properties, c("name", "valid", "retry_hint"))

  responses <- DBI::dbGetQuery(
    con,
    "SELECT question_id, question_text, answer_raw, answer_extracted, valid,
       method FROM responses ORDER BY response_id"
  )
  expect_equal(responses$question_id, c("name", "flavor", "why"))
  expect_equal(responses$method, c("form", "chat", "form"))
  expect_equal(
    responses$question_text,
    c("Name?", "Ana, flavor?", "Why mint, Ana?")
  )
  expect_equal(responses$answer_raw, c("ana", "mint", "it is fresh"))
  expect_equal(responses$answer_extracted, c("Ana", "mint", "fresh taste"))
  expect_equal(as.logical(responses$valid), c(TRUE, TRUE, TRUE))
  expect_equal(
    engine$answers_so_far(),
    list(name = "Ana", flavor = "mint", why = "fresh taste")
  )
})

test_that("the current prompt is generated once for both views", {
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x"),
    list(flavor = "mint", valid = TRUE),
    list(content = "Why mint, Ana?")
  )
  engine <- SurveySession$new(test_spec(), chat, local_sqlite())
  engine$start()
  expect_equal(engine$first_question(), "Name?")
  expect_equal(engine$current_prompt()$text, "Name?")

  engine$submit_form("Ana")
  engine$process_input("mint")
  calls <- length(chat$log$prompts)
  prompt <- engine$current_prompt()

  expect_equal(prompt$id, "why")
  expect_equal(prompt$text, "Why mint, Ana?")
  expect_identical(engine$current_prompt(), prompt)
  expect_length(chat$log$prompts, calls)
})

test_that("a form value with the wrong type records nothing", {
  con <- local_sqlite()
  engine <- SurveySession$new(test_spec(), fake_chat(), con)
  engine$start()
  engine$first_question()

  result <- engine$submit_form("  ")
  expect_null(result$message)
  expect_false(result$complete)
  expect_match(result$error, "answer this question")
  expect_equal(nrow(responses_of(con)), 0)
  expect_equal(engine$current_prompt()$id, "name")
  expect_equal(DBI::dbGetQuery(con, "SELECT retry_count FROM sessions")[[1]], 0)
})

test_that("typed form text that is not valid is asked again up to `tries`", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE),
    list(name = "??", valid = FALSE),
    list(content = "x")
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  retry <- engine$submit_form("asdf")
  expect_equal(
    retry,
    list(message = NULL, complete = FALSE, error = test_spec()$messages$retry)
  )
  expect_equal(engine$current_prompt()$id, "name")

  # After the last retry, the answer is kept and the survey moves on
  kept <- engine$submit_form("asdf")
  expect_match(kept$message, "flavor")

  responses <- DBI::dbGetQuery(
    con,
    "SELECT retry_attempt, valid, method FROM responses ORDER BY response_id"
  )
  expect_equal(responses$retry_attempt, c(0, 1))
  expect_equal(as.logical(responses$valid), c(FALSE, FALSE))
  expect_equal(responses$method, c("form", "form"))
  expect_equal(DBI::dbGetQuery(con, "SELECT retry_count FROM sessions")[[1]], 1)
})

test_that("the chat and the form share one retry count", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "??", valid = FALSE),
    list(name = "Ana", valid = TRUE),
    list(content = "x")
  )
  spec <- test_spec() |> set_config(tries = 2)
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  engine$process_input("?")
  engine$submit_form("Ana")

  responses <- DBI::dbGetQuery(
    con,
    "SELECT retry_attempt, valid, method FROM responses ORDER BY response_id"
  )
  expect_equal(responses$retry_attempt, c(0, 1))
  expect_equal(as.logical(responses$valid), c(FALSE, TRUE))
  expect_equal(responses$method, c("chat", "form"))
})

test_that("a fixed choice in the form needs no LLM call", {
  con <- local_sqlite()
  spec <- choice_spec(answer = ellmer::type_enum(c("cone", "cup"), "Serve"))
  chat <- fake_chat(list(name = "Ana", valid = TRUE))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")
  calls <- length(chat$log$prompts)

  expect_true(engine$submit_form("cup")$complete)
  expect_length(chat$log$prompts, calls)
  expect_equal(as.logical(responses_of_valid(con)), c(TRUE, TRUE))
})

test_that("a picked card needs no check, but typed text does", {
  prompt <- list(generated = "Waffle", fixed = "Plain")
  string <- list(answer = ellmer::type_string(), own_valid = FALSE)
  own <- list(answer = ellmer::type_enum(c("a", "b")), own_valid = TRUE)
  enum <- list(answer = ellmer::type_enum(c("a", "b")), own_valid = FALSE)
  integer <- list(answer = ellmer::type_integer(), own_valid = FALSE)

  expect_false(form_needs_validation(string, prompt, "Plain"))
  expect_false(form_needs_validation(string, prompt, "Waffle"))
  expect_true(form_needs_validation(string, prompt, "Rocky road"))
  expect_true(form_needs_validation(string, list(), "Rocky road"))
  expect_false(form_needs_validation(string, list(), ""))
  expect_false(form_needs_validation(enum, list(), "a"))
  expect_false(form_needs_validation(integer, list(), "34"))
  expect_true(form_needs_validation(own, list(), "a"))
})

test_that("a question with its own rule checks a form number with the LLM", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question(
      "age",
      text = "Age?",
      answer = ellmer::type_integer("Age"),
      valid = "a plausible age from 13 to 120"
    )
  chat <- fake_chat(list(age = 400L, valid = FALSE))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(engine$submit_form(400)$error, spec$messages$retry)
  expect_match(chat$log$prompts[1], "Reply: 400", fixed = TRUE)
})

test_that("a failed LLM check keeps the form answer with no valid flag", {
  con <- local_sqlite()
  chat <- fake_chat(simpleError("API down"), list(content = "x"))
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()

  expect_warning(
    message <- engine$submit_form("Ana")$message,
    "keeps it"
  )
  expect_match(message, "Ana, flavor?", fixed = TRUE)
  expect_true(is.na(responses_of_valid(con)))
  expect_equal(engine$answers_so_far(), list(name = "Ana"))
})

test_that("the form gives no answer after the survey is complete", {
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "x"),
    list(flavor = "mint", valid = TRUE),
    list(content = "y"),
    list(why = "fresh", valid = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, local_sqlite())
  engine$start()
  engine$first_question()
  engine$submit_form("Ana")
  engine$submit_form("mint")
  engine$submit_form("fresh")

  expect_null(engine$current_prompt())
  expect_equal(
    engine$submit_form("again"),
    list(message = NULL, complete = TRUE)
  )
})

test_that("a retry shows the LLM hint, or the retry message without one", {
  hint <- "That doesn't look like a name. Could you tell me your first name?"
  chat <- fake_chat(
    list(name = "??", valid = FALSE, retry_hint = paste0(" ", hint, " ")),
    list(name = "??", valid = FALSE, retry_hint = "  "),
    list(name = "??", valid = FALSE, retry_hint = NA_character_)
  )
  spec <- test_spec() |> set_config(tries = 3)
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("?")$message, hint)
  expect_equal(engine$process_input("?")$message, spec$messages$retry)
  expect_equal(engine$submit_form("asdf")$error, spec$messages$retry)
  expect_match(
    chat$log$types[[1]]@properties$retry_hint@description,
    "valid is FALSE"
  )
  expect_false(chat$log$types[[1]]@properties$retry_hint@required)
})

test_that("a form retry shows the LLM hint under the field", {
  hint <- "Please enter your age in years."
  chat <- fake_chat(list(age = 400L, valid = FALSE, retry_hint = hint))
  spec <- survey_spec() |>
    add_question(
      "age",
      text = "Age?",
      answer = ellmer::type_integer("Age"),
      valid = "a plausible age from 13 to 120"
    )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  expect_equal(engine$submit_form(400)$error, hint)
})

# Three questions: the second applies only to a user who attends
when_spec <- function() {
  survey_spec() |>
    set_config(tries = 1) |>
    add_question(
      "attending",
      text = "Will you attend?",
      answer = ellmer::type_enum(c("Yes", "No"), "Attending")
    ) |>
    add_question(
      "dinner",
      text = "Will you stay for dinner?",
      answer = ellmer::type_boolean("Dinner"),
      when = ~ attending == "Yes"
    ) |>
    add_question(
      "comment",
      text = "Any comments?",
      answer = ellmer::type_string("Comment", required = FALSE)
    )
}

test_that("a question whose `when` rule is FALSE is skipped with no row", {
  con <- local_sqlite()
  chat <- fake_chat(list(comment = "none", valid = TRUE))
  engine <- SurveySession$new(when_spec(), chat, con)
  engine$start()
  engine$first_question()

  expect_equal(engine$submit_form("No")$message, "Any comments?")
  expect_equal(engine$progress(), list(current = 2, total = 2))
  expect_true(engine$process_input("none")$complete)

  expect_equal(responses_of(con)$question_id, c("attending", "comment"))
  expect_named(engine$answers_so_far(), c("attending", "comment"))
})

test_that("a question whose `when` rule is TRUE is asked", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(attending = "Yes", valid = TRUE),
    list(dinner = TRUE, valid = TRUE)
  )
  engine <- SurveySession$new(when_spec(), chat, con)
  engine$start()
  engine$first_question()
  expect_equal(engine$progress(), list(current = 1, total = 3))

  expect_equal(engine$process_input("yes")$message, "Will you stay for dinner?")
  expect_equal(engine$progress(), list(current = 2, total = 3))
  expect_equal(engine$submit_form("TRUE")$message, "Any comments?")
  expect_equal(engine$progress(), list(current = 3, total = 3))
  expect_equal(
    responses_of(con)$question_id,
    c("attending", "dinner")
  )
})

test_that("a `when` rule on a skipped answer is FALSE", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("Name", required = FALSE)
    ) |>
    add_question(
      "nickname",
      text = "Nickname for {name}?",
      answer = ellmer::type_string("Nickname"),
      when = ~ name != "Bob"
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  engine <- SurveySession$new(spec, fake_chat(), con)
  engine$start()
  engine$first_question()

  expect_equal(engine$submit_form("")$message, "End?")
})

test_that("early answers leave out questions that do not apply yet", {
  con <- local_sqlite()
  spec <- when_spec() |>
    add_question(
      "dessert",
      text = "Dessert?",
      answer = ellmer::type_string("Dessert"),
      when = ~ isTRUE(dinner)
    ) |>
    add_question(
      "parking",
      text = "Do you need parking?",
      answer = ellmer::type_string("Parking"),
      when = ~ attending == "Yes"
    )
  chat <- fake_chat(
    list(attending = "Yes", valid = TRUE, comment = "great"),
    list(dinner = TRUE, valid = TRUE, parking = "car"),
    list(dessert = "pie", valid = TRUE)
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  # Each rule needs an answer that is not known yet
  expect_equal(
    engine$process_input("yes, great event")$message,
    "Will you stay for dinner?"
  )
  expect_named(
    chat$log$types[[1]]@properties,
    c("attending", "valid", "retry_hint", "comment")
  )

  # Attending is known now, so parking can be answered early
  expect_equal(engine$process_input("yes, by car")$message, "Dessert?")
  expect_named(
    chat$log$types[[2]]@properties,
    c("dinner", "valid", "retry_hint", "parking")
  )
  expect_true(engine$process_input("pie")$complete)
  expect_equal(
    responses_of(con)$question_id,
    c("attending", "comment", "dinner", "parking", "dessert")
  )
})

test_that("a `when` rule that fails is FALSE and gives a warning", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question("a", text = "A?", answer = ellmer::type_string("A")) |>
    add_question(
      "b",
      text = "B?",
      answer = ellmer::type_string("B"),
      when = ~ stop("boom") || a == "x"
    ) |>
    add_question("c", text = "C?", answer = ellmer::type_string("C"))
  chat <- fake_chat(list(a = "x", valid = TRUE))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_warning(
    expect_equal(engine$process_input("x")$message, "C?"),
    "rule of question"
  )
})
multi_spec <- function() {
  survey_spec() |>
    set_config(tries = 1) |>
    add_question(
      "diet",
      text = "Diet?",
      answer = ellmer::type_array(
        ellmer::type_enum(c("Vegetarian", "No nuts")),
        "Dietary needs"
      )
    ) |>
    add_question(
      "dish",
      text = "Which veggie dish?",
      answer = ellmer::type_string("Dish"),
      when = ~ "Vegetarian" %in% diet
    ) |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
}

test_that("a multi-select answer is stored as JSON and used by a rule", {
  con <- local_sqlite()
  engine <- SurveySession$new(multi_spec(), fake_chat(), con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$submit_form(c("Vegetarian", "No nuts"))$message,
    "Which veggie dish?"
  )
  expect_equal(engine$answers_so_far()$diet, c("Vegetarian", "No nuts"))
  row <- DBI::dbGetQuery(
    con,
    "SELECT answer_raw, answer_extracted FROM responses"
  )
  expect_equal(row$answer_raw, '["Vegetarian","No nuts"]')
  expect_equal(row$answer_extracted, '["Vegetarian","No nuts"]')
  expect_equal(
    jsonlite::fromJSON(row$answer_extracted),
    c("Vegetarian", "No nuts")
  )
})

test_that("the chat extracts a multi-select answer as JSON", {
  con <- local_sqlite()
  chat <- fake_chat(list(diet = list("No nuts"), valid = TRUE))
  engine <- SurveySession$new(multi_spec(), chat, con)
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("no nuts please")$message, "End?")
  expect_equal(
    DBI::dbGetQuery(
      con,
      "SELECT answer_extracted FROM responses"
    )$answer_extracted,
    '["No nuts"]'
  )
})

test_that("a chat date that is not ISO is asked again", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_config(tries = 1) |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date") |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  chat <- fake_chat(
    list(day = "next Tuesday", valid = TRUE),
    list(day = "2026-11-03", valid = TRUE)
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("next Tuesday")$message,
    spec$messages$date
  )
  expect_equal(engine$process_input("November 3")$message, "End?")
  expect_equal(
    DBI::dbGetQuery(con, "SELECT valid FROM responses")$valid,
    c(0, 1)
  )
})

test_that("a chat date that never fits is not kept after the retries", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_config(tries = 1) |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date") |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  chat <- fake_chat(
    list(day = "next Tuesday", valid = TRUE),
    list(day = "Tuesday", valid = TRUE)
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  engine$process_input("next Tuesday")
  # After the last retry, the survey moves on with no date
  expect_equal(engine$process_input("Tuesday")$message, "End?")
  expect_null(engine$answers_so_far()$day)
  expect_equal(
    DBI::dbGetQuery(
      con,
      "SELECT answer_extracted FROM responses"
    )$answer_extracted,
    c(NA_character_, NA_character_)
  )
})

test_that("early answers store a multi-select as JSON and skip a bad date", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N")) |>
    add_question(
      "diet",
      text = "Diet?",
      answer = ellmer::type_array(ellmer::type_enum(c("Vegan", "Halal")))
    ) |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date")
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE, diet = list("Vegan"), day = "soon")
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("Ana, vegan, soon")$message, "Day?")
  expect_equal(engine$answers_so_far()$diet, "Vegan")
  rows <- DBI::dbGetQuery(
    con,
    "SELECT question_id, answer_extracted FROM responses ORDER BY response_id"
  )
  expect_equal(rows$question_id, c("name", "diet"))
  expect_equal(rows$answer_extracted, c("Ana", '["Vegan"]'))
})

test_that("the date retry message can be changed", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(date = "Datum bitte als JJJJ-MM-TT.") |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date")
  engine <- SurveySession$new(
    spec,
    fake_chat(list(day = "soon", valid = TRUE)),
    con
  )
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("soon")$message,
    "Datum bitte als JJJJ-MM-TT."
  )
})

test_that("a form date with its own rule gets today's date in the check", {
  con <- local_sqlite()
  local_mocked_bindings(now = function() as.POSIXct("2026-10-03 12:00:00"))
  spec <- survey_spec() |>
    add_question(
      "day",
      "Day?",
      ellmer::type_string("Day"),
      input = "date",
      valid = "a date in the future"
    )
  chat <- fake_chat(list(day = "2026-11-03", valid = TRUE))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()
  engine$submit_form(as.Date("2026-11-03"))

  expect_match(
    chat$log$types[[1]]@properties$day@description,
    "Today is 2026-10-03.",
    fixed = TRUE
  )
})

test_that("a value from an input in the chat is recorded as a chat answer", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    add_question("day", "Day?", ellmer::type_string("Day"), input = "date") |>
    add_question("end", text = "End?", answer = ellmer::type_string("End"))
  engine <- SurveySession$new(spec, fake_chat(), con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$submit_form(as.Date("2026-11-03"), method = "chat")$message,
    "End?"
  )
  row <- DBI::dbGetQuery(con, "SELECT answer_extracted, method FROM responses")
  expect_equal(row$answer_extracted, "2026-11-03")
  expect_equal(row$method, "chat")
})

test_that("a generated completion reflects the answers before the format", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(
      completion = prompt_llm(
        "Reflect on {flavor}.",
        format = "{content}\n\nBye {name}"
      )
    ) |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N")) |>
    add_question("flavor", text = "Flavor?", answer = ellmer::type_string("F"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(flavor = "mint", valid = TRUE),
    list(content = "Mint is a fresh pick.")
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  result <- engine$process_input("mint")
  expect_true(result$complete)
  expect_equal(result$message, "Mint is a fresh pick.\n\nBye Ana")
  expect_match(chat$log$prompts[3], "Reflect on mint.", fixed = TRUE)
  # The model sees every answer, so it reacts only to what the user said
  expect_match(chat$log$prompts[3], "- Flavor? (flavor): mint", fixed = TRUE)
  # The closing is the last message, so it asks nothing
  expect_match(chat$log$prompts[3], "do not ask a question", fixed = TRUE)
  expect_equal(result$closing$template, "{content}\n\nBye {name}")
  expect_equal(result$closing$data$content, "Mint is a fresh pick.")
})

test_that("a failed generated completion shows the format alone", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(
      completion = prompt_llm("Reflect.", format = "{content}\n\nBye {name}")
    ) |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N"))
  chat <- fake_chat(list(name = "Ana", valid = TRUE), simpleError("API down"))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_warning(result <- engine$process_input("Ana"), "completion")
  expect_equal(result$message, "Bye Ana")
})

test_that("a failed generated completion uses the content fallback", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(
      completion = prompt_llm(
        "Reflect.",
        format = "Thanks, {name}. {content|Great talk.} Bye."
      )
    ) |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N"))
  chat <- fake_chat(list(name = "Ana", valid = TRUE), simpleError("API down"))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_warning(result <- engine$process_input("Ana"), "completion")
  expect_equal(result$message, "Thanks, Ana. Great talk. Bye.")
})

test_that("a failed generated completion leaves no gap without a fallback", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(
      completion = prompt_llm(
        "Reflect.",
        format = "Hi\n\n{content}\n\nBye {name}"
      )
    ) |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N"))
  chat <- fake_chat(list(name = "Ana", valid = TRUE), simpleError("API down"))
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_warning(result <- engine$process_input("Ana"), "completion")
  expect_equal(result$message, "Hi\n\nBye Ana")
})

test_that("generated choices of an enum keep only its values", {
  spec <- choice_spec(
    answer = ellmer::type_enum(c("cone", "cup"), "Serve"),
    choices = prompt_llm("Serving ideas for {name}")
  )
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(choices = c("Cup", "waffle bowl"))
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  expect_equal(engine$current_prompt()$generated, "cup")
})

test_that("a static completion keeps its spacing as written", {
  con <- local_sqlite()
  spec <- survey_spec() |>
    set_messages(completion = "Bye {name}  \nSee you") |>
    add_question("name", text = "Name?", answer = ellmer::type_string("N"))
  engine <- SurveySession$new(
    spec,
    fake_chat(list(name = "Ana", valid = TRUE)),
    con
  )
  engine$start()
  engine$first_question()

  expect_equal(engine$process_input("Ana")$message, "Bye Ana  \nSee you")
})

test_that("an adaptive question that the answers already cover is skipped", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE),
    list(skip = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  expect_no_warning(result <- engine$process_input("mint, it is so fresh"))
  expect_true(result$complete)
  expect_equal(responses_of(con)$question_id, c("name", "flavor"))
  # The model sees every answer so far and may decline to ask
  expect_match(chat$log$prompts[4], "Answers so far:", fixed = TRUE)
  # Each answer comes with the question that the user saw
  expect_match(
    chat$log$prompts[4],
    "- Ana, flavor? (flavor): mint",
    fixed = TRUE
  )
  expect_true("skip" %in% names(chat$log$types[[4]]@properties))
  # The question is open, with no examples or products to lead the user,
  # unless the author's prompt asks for them
  expect_match(
    chat$log$prompts[4],
    "Unless the prompt above asks for them, do not list example answers",
    fixed = TRUE
  )
})

test_that("with skip_answered = FALSE, an adaptive question is always asked", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE),
    list(skip = TRUE, content = "Why mint, Ana?")
  )
  spec <- set_config(test_spec(), skip_answered = FALSE)
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  result <- engine$process_input("mint")
  expect_false(result$complete)
  expect_match(result$message, "Why mint, Ana?", fixed = TRUE)
  # The model is not asked to decide a skip
  expect_false("skip" %in% names(chat$log$types[[4]]@properties))
  expect_no_match(chat$log$prompts[4], "Set skip", fixed = TRUE)
  expect_no_match(
    chat$log$types[[4]]@properties$content@description,
    "skip",
    fixed = TRUE
  )
})

test_that("the cap on generated enum choices comes after the enum filter", {
  spec <- choice_spec(
    answer = ellmer::type_enum(c("cone", "cup"), "Serve"),
    choices = prompt_llm("Serving ideas for {name}")
  )
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(choices = c("waffle", "bowl", "plate", "stick", "Cup"))
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()
  engine$process_input("Ana")

  expect_equal(engine$current_prompt()$generated, "cup")
})

test_that("form validation sees the earlier answers for context", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  engine$submit_form("Ana")
  engine$submit_form("mint")

  expect_match(
    chat$log$prompts[3],
    "Answers so far:\n- Name? (name): Ana",
    fixed = TRUE
  )
  expect_match(chat$log$prompts[3], "context only", fixed = TRUE)
})

test_that("validation sees the earlier answers for context", {
  con <- local_sqlite()
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Ana is a nice name."),
    list(flavor = "mint", valid = TRUE)
  )
  engine <- SurveySession$new(test_spec(), chat, con)
  engine$start()
  engine$first_question()
  engine$process_input("Ana")
  engine$process_input("mint")

  expect_no_match(chat$log$prompts[1], "Answers so far", fixed = TRUE)
  expect_match(
    chat$log$prompts[3],
    "Answers so far:\n- Name? (name): Ana",
    fixed = TRUE
  )
})

test_that("an intro asks no question, even when the model writes one", {
  spec <- survey_spec() |>
    add_question(
      "name",
      text = "Name?",
      answer = ellmer::type_string("Name")
    ) |>
    add_question(
      "flavor",
      text = "Flavor?",
      intro = prompt_llm("React to {name}", format = "{content}"),
      answer = ellmer::type_string("Flavor")
    )
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(content = "Nice to meet you, Ana. What else do you like?")
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  result <- engine$process_input("Ana")
  expect_equal(engine$current_prompt()$intro, "Nice to meet you, Ana.")
  expect_no_match(result$message, "What else", fixed = TRUE)
})

test_that("an early answer comes with its fixed question text", {
  chat <- fake_chat(
    list(name = "Ana", flavor = "mint", valid = TRUE),
    list(content = "Why mint?")
  )
  engine <- SurveySession$new(test_spec(), chat, local_sqlite())
  engine$start()
  engine$first_question()
  engine$process_input("Ana, and I love mint")

  # The flavor question was never shown, so the adaptive call gets its
  # fixed text
  expect_match(
    chat$log$prompts[2],
    "- Ana, flavor? (flavor): mint",
    fixed = TRUE
  )
})
