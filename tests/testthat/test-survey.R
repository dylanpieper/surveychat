responses_of <- function(con) {
  DBI::dbGetQuery(
    con,
    "SELECT question_id, question_text, input_extracted, retry_attempt
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
