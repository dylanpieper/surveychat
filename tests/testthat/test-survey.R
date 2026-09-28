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
    engine$process_input("fresh"),
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

test_that("an enum question ends with its values as a separate part", {
  con <- local_sqlite()
  spec <- choice_spec(answer = ellmer::type_enum(c("cone", "cup"), "Serve"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(serve = "cone", valid = TRUE)
  )
  engine <- SurveySession$new(spec, chat, con)
  engine$start()
  engine$first_question()

  expect_equal(
    engine$process_input("Ana")$message,
    c(
      "Cone or cup, Ana?",
      paste(
        '* <span class="suggestion">cone</span>',
        '* <span class="suggestion">cup</span>',
        sep = "\n"
      )
    )
  )
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
  expect_named(chat$log$types[[1]]@properties, c("name", "valid", "flavor"))
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
  expect_named(chat$log$types[[1]]@properties, c("name", "valid"))
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

test_that("preset choices show on any answer type", {
  spec <- choice_spec(choices = c("cone", "cup"))
  engine <- SurveySession$new(
    spec,
    fake_chat(list(name = "Ana", valid = TRUE)),
    local_sqlite()
  )
  engine$start()
  engine$first_question()

  message <- engine$process_input("Ana")$message
  expect_match(message[2], '<span class="suggestion">cup</span>', fixed = TRUE)
})

test_that("generated choices follow the suggested note", {
  spec <- choice_spec(choices = prompt_llm("Serving ideas for {name}"))
  chat <- fake_chat(
    list(name = "Ana", valid = TRUE),
    list(choices = c("Cone", " cup ", "Cone", ""))
  )
  engine <- SurveySession$new(spec, chat, local_sqlite())
  engine$start()
  engine$first_question()

  message <- engine$process_input("Ana")$message
  expect_equal(message[1], "Cone or cup, Ana?")
  expect_equal(
    message[2],
    paste0(
      spec$messages$suggested,
      "\n\n",
      '* <span class="suggestion">Cone</span>\n',
      '* <span class="suggestion">cup</span>'
    )
  )
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

test_that("fixed choices always show after the generated ones", {
  plain <- '* <span class="suggestion">Plain</span>'
  run <- function(generation) {
    spec <- choice_spec(choices = list(prompt_llm("Ideas for {name}"), "Plain"))
    chat <- fake_chat(list(name = "Ana", valid = TRUE), generation)
    engine <- SurveySession$new(spec, chat, local_sqlite())
    engine$start()
    engine$first_question()
    suppressWarnings(engine$process_input("Ana")$message[2])
  }

  # A generated choice that repeats a fixed one is dropped
  expect_equal(
    run(list(choices = c("Cone", "plain"))),
    paste0(
      survey_spec()$messages$suggested,
      "\n\n",
      '* <span class="suggestion">Cone</span>',
      "\n\n",
      plain
    )
  )
  expect_equal(run(simpleError("API down")), plain)
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
  expect_equal(result, list(message = "Bye Ana", complete = TRUE))
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

  expect_equal(last, list(message = "Bye Ana", complete = TRUE))
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
