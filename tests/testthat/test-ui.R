test_that("the progress cue shows the question and the bar width", {
  expect_snapshot(cat(as.character(survey_progress(2, 4))))
  expect_snapshot(cat(as.character(survey_progress(4, 4, complete = TRUE))))
})

test_that("the footer hides the namespaced chat input", {
  expect_snapshot(cat(as.character(survey_complete("Done", "survey-chat"))))
  expect_snapshot(cat(as.character(
    survey_complete("Unavailable", "survey-chat", status = "locked")
  )))
})

test_that("survey_ui() namespaces its ids", {
  html <- as.character(survey_ui("survey", title = "Test"))

  expect_match(html, 'id="survey-chat"', fixed = TRUE)
  expect_match(html, 'id="survey-progress"', fixed = TRUE)
  expect_match(html, 'id="survey-footer"', fixed = TRUE)
  # The progress cue is in the header only
  expect_length(gregexpr('id="survey-progress"', html)[[1]], 1)
})

test_that("survey_chat_ui() makes a chat with a footer and an optional drawer", {
  html <- as.character(survey_chat_ui("survey"))
  expect_match(html, 'id="survey-chat"', fixed = TRUE)
  expect_match(html, 'id="survey-progress"', fixed = TRUE)
  expect_match(html, 'id="survey-footer"', fixed = TRUE)
  expect_match(
    html,
    'id="survey-waiter" class="sb-overlay sb-waiter"',
    fixed = TRUE
  )
  expect_no_match(html, "<shiny-chat-drawer", fixed = TRUE)

  with_drawer <- as.character(survey_chat_ui(
    "survey",
    drawer = shinychat::chat_drawer(title = "Scoop card", open = FALSE),
    progress = FALSE
  ))
  expect_match(with_drawer, "<shiny-chat-drawer", fixed = TRUE)
  expect_match(with_drawer, 'title="Scoop card"', fixed = TRUE)
  expect_no_match(with_drawer, 'id="survey-progress"', fixed = TRUE)
})

test_that("the drawer toggle sits beside the input with the drawer title", {
  html <- as.character(survey_chat_ui(
    "survey",
    drawer = shinychat::chat_drawer(title = "Scoop card")
  ))
  expect_match(html, 'data-display-if="output.drawer_ready"', fixed = TRUE)
  expect_match(html, 'data-ns-prefix="survey-"', fixed = TRUE)
  expect_match(html, 'id="survey-drawer_toggle"', fixed = TRUE)
  expect_match(html, "Scoop card</span>", fixed = TRUE)

  untitled <- as.character(survey_chat_ui(
    "survey",
    drawer = shinychat::chat_drawer()
  ))
  expect_match(untitled, "Your answers", fixed = TRUE)
  expect_no_match(
    as.character(survey_chat_ui("survey")),
    "drawer_toggle",
    fixed = TRUE
  )
})

test_that("two survey chats on one page add the styles once", {
  head <- htmltools::renderTags(htmltools::tagList(
    survey_chat_ui("a"),
    survey_chat_ui("b")
  ))$head
  expect_length(gregexpr(".sb-progress {", head, fixed = TRUE)[[1]], 1)
})

test_that("survey_chat_ui() checks its arguments", {
  expect_snapshot(survey_chat_ui("survey", drawer = TRUE), error = TRUE)
  expect_snapshot(survey_chat_ui("survey", progress = "yes"), error = TRUE)
})

test_that("suggestion_cards() makes one escaped card for each choice", {
  expect_null(suggestion_cards(NULL))
  expect_equal(
    suggestion_cards(c("cone", "a & b")),
    paste(
      '* <span class="suggestion">cone</span>',
      '* <span class="suggestion">a &amp; b</span>',
      sep = "\n"
    )
  )
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

test_that("bot_response() adds the later parts whole", {
  result <- NULL
  promises::then(
    coro::async_collect(bot_response(
      c("hi", "* card"),
      character_delay = 0,
      delay_variance = 0
    )),
    onFulfilled = \(x) result <<- x
  )
  deadline <- Sys.time() + 5
  while (is.null(result) && Sys.time() < deadline) {
    later::run_now(0.05)
  }

  expect_equal(unlist(result), c("h", "i", "\n\n* card"))
})

test_that("run_example() lists the examples and rejects an unknown name", {
  expect_true("icecream" %in% run_example(NULL))
  expect_snapshot(run_example("nope"), error = TRUE)
})

test_that("example_chat() resolves the env var and a string", {
  seen <- NULL
  local_mocked_bindings(
    chat = function(name, ...) {
      seen <<- list(name = name, args = list(...))
      fake_chat()
    },
    .package = "ellmer"
  )

  withr::local_envvar(SURVEYCHAT_CHAT = "ollama/llama3.2")
  example_chat(NULL)
  expect_equal(seen$name, "ollama/llama3.2")
  expect_equal(seen$args$echo, "none")

  example_chat("openai")
  expect_equal(seen$name, "openai")
  expect_equal(seen$args$echo, "none")
})

test_that("example_chat() passes a Chat through and rejects other values", {
  chat <- fake_chat()
  expect_identical(example_chat(chat), chat)
  withr::local_envvar(SURVEYCHAT_CHAT = NA)
  expect_snapshot(example_chat(NULL), error = TRUE)
  expect_snapshot(example_chat(1), error = TRUE)
  expect_error(example_chat(""), "must be a string")
  expect_error(example_chat(NA_character_), "must be a string")
  expect_error(example_chat(c("openai", "ollama")), "must be a string")
})

test_that("example_chat() keeps the ellmer error for an unknown provider", {
  local_mocked_bindings(
    chat = \(...) stop("Can't find provider."),
    .package = "ellmer"
  )

  err <- expect_error(example_chat("nope/x"), "Could not make a chat")
  expect_match(conditionMessage(err$parent), "Can't find provider")
})

test_that("run_example() stops before runApp() when the credentials fail", {
  skip_if_not_installed("RSQLite")
  fake_provider <- S7::new_class(
    "fake_provider",
    properties = list(credentials = S7::class_function)
  )
  chat <- list(
    get_provider = \() fake_provider(credentials = \() stop("no key"))
  )
  class(chat) <- "Chat"
  ran <- FALSE
  local_mocked_bindings(runApp = \(...) ran <<- TRUE, .package = "shiny")

  expect_snapshot(run_example(chat = chat), error = TRUE)
  expect_false(ran)
})

test_that("run_example() hands the chat to the app and resets the option", {
  skip_if_not_installed("RSQLite")
  chat <- fake_chat()
  inside <- NULL
  local_mocked_bindings(
    runApp = \(...) inside <<- getOption("surveychat.example_chat"),
    .package = "shiny"
  )
  withr::local_options(surveychat.example_chat = "old")

  run_example(chat = chat)

  expect_identical(inside, chat)
  expect_equal(getOption("surveychat.example_chat"), "old")
})
