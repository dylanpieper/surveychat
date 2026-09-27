test_that("the progress cue shows the question and the bar width", {
  expect_snapshot(cat(as.character(survey_progress(2, 4))))
  expect_snapshot(cat(as.character(survey_progress(4, 4, complete = TRUE))))
})

test_that("the footer hides the namespaced chat input", {
  expect_snapshot(cat(as.character(survey_complete("Done", "survey-chat"))))
})

test_that("survey_ui() namespaces its ids", {
  html <- as.character(survey_ui("survey", title = "Test"))

  expect_match(html, 'id="survey-chat"', fixed = TRUE)
  expect_match(html, 'id="survey-progress"', fixed = TRUE)
  expect_match(html, 'id="survey-footer"', fixed = TRUE)
})

test_that("bot_response() streams one character at a time", {
  result <- NULL
  failure <- NULL
  promises::then(
    coro::async_collect(bot_response(
      "hi",
      character_delay = 0,
      delay_variance = 0
    )),
    onFulfilled = \(x) result <<- x,
    onRejected = \(err) failure <<- err
  )
  deadline <- Sys.time() + 5
  while (is.null(result) && is.null(failure) && Sys.time() < deadline) {
    later::run_now(0.05)
  }

  expect_null(failure)
  expect_equal(unlist(result), c("h", "i"))
})

test_that("run_example() lists the examples and rejects an unknown name", {
  expect_true("icecream" %in% run_example(NULL))
  expect_snapshot(run_example("nope"), error = TRUE)
})
