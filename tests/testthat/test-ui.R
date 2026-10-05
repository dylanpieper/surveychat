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
  expect_equal(count_matches('id="survey-progress"', html), 1)
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
  expect_equal(count_matches(".sb-progress {", head, fixed = TRUE), 1)
})

test_that("survey_chat_ui() checks its arguments", {
  expect_snapshot(survey_chat_ui("survey", drawer = TRUE), error = TRUE)
  expect_snapshot(survey_chat_ui("survey", progress = "yes"), error = TRUE)
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
  expect_contains(
    run_example(NULL),
    c("chat-sidebar-drawer", "panel-chat-form")
  )
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

  withr::local_envvar(SURVEYCHAT_MODEL = "ollama/llama3.2")
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
  withr::local_envvar(SURVEYCHAT_MODEL = NA)
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

test_that("survey_panel_ui() holds the chat and the form behind the view", {
  html <- as.character(survey_panel_ui("survey", title = "About you"))

  expect_match(html, "About you", fixed = TRUE)
  expect_match(html, 'id="survey-method"', fixed = TRUE)
  expect_match(html, 'id="survey-form"', fixed = TRUE)
  expect_match(html, 'id="survey-chat"', fixed = TRUE)
  expect_match(html, "output.view === &#39;side_by_side&#39;", fixed = TRUE)
  expect_match(html, "output.view === &#39;form&#39;", fixed = TRUE)
  expect_equal(count_matches('data-ns-prefix="survey-"', html), 2)
  expect_error(survey_panel_ui("survey", title = 1), "title")
})

test_that("the view picker is one radio group of icon buttons", {
  html <- as.character(view_picker(
    "survey-view_pick",
    "form",
    c("form", "chat", "side_by_side")
  ))

  expect_match(html, 'id="survey-view_pick"', fixed = TRUE)
  expect_match(html, "shiny-input-radiogroup", fixed = TRUE)
  expect_equal(count_matches('name="survey-view_pick"', html), 3)
  expect_match(html, 'value="form" autocomplete="off" checked', fixed = TRUE)
  expect_equal(count_matches("checked", html), 1)
  for (label in c("Form", "AI chat", "Side by side")) {
    expect_match(html, sprintf('aria-label="%s"', label), fixed = TRUE)
  }
})

test_that("survey_panel_ui() puts the controls in the header with no title", {
  untitled <- as.character(survey_panel_ui("x"))
  titled <- as.character(survey_panel_ui("x", title = "About you"))

  expect_no_match(untitled, "About you", fixed = TRUE)
  expect_match(titled, "<span>About you</span>", fixed = TRUE)
  for (html in c(untitled, titled)) {
    expect_match(html, 'id="x-method"', fixed = TRUE)
    expect_match(html, 'id="x-progress"', fixed = TRUE)
  }
})

test_that("survey_status() puts rendered markdown in a block", {
  plain <- as.character(survey_status("Done"))
  rendered <- as.character(survey_status(shiny::markdown("Done\n\nBye")))

  expect_match(plain, "<span>Done</span>", fixed = TRUE)
  expect_match(rendered, '<div class="sb-status-text">', fixed = TRUE)
  expect_equal(count_matches("<p>", rendered), 2)
})

test_that("the view buttons follow the order of the views", {
  order_of <- function(views) {
    html <- as.character(view_picker("v", views[[1]], views))
    values <- regmatches(html, gregexpr('value="[a-z_]+"', html))[[1]]
    gsub('value=|"', "", values)
  }

  expect_equal(order_of(c("chat", "form")), c("chat", "form"))
  expect_equal(
    order_of(c("side_by_side", "form", "chat")),
    c("side_by_side", "form", "chat")
  )
})

test_that("only a string, an enum, or a yes or no gets radio buttons in the chat", {
  spec <- survey_spec() |>
    add_question(
      "age",
      text = "Age?",
      answer = ellmer::type_integer(),
      choices = c("Under 18", "18 or over")
    )
  question <- spec$questions[[1]]
  prompt <- list(id = "age", text = "Age?", fixed = question$choices$fixed)

  expect_false(has_chat_input(question))
  expect_null(chat_input(shiny::NS("s"), prompt, question))
})

test_that("an enum with choices shows those choices in the chat and the form", {
  spec <- survey_spec() |>
    add_question(
      "serve",
      text = "Serve?",
      answer = ellmer::type_enum(c("Cone", "Cup", "Waffle")),
      choices = c("Cone", "Cup")
    )
  question <- spec$questions[[1]]
  prompt <- list(id = "serve", text = "Serve?", fixed = question$choices$fixed)

  for (html in c(
    as.character(chat_input(shiny::NS("s"), prompt, question)),
    as.character(form_input(shiny::NS("s"), prompt, question))
  )) {
    expect_match(html, 'value="Cup"', fixed = TRUE)
    expect_no_match(html, 'value="Waffle"', fixed = TRUE)
    expect_no_match(html, 'data-value="Waffle"', fixed = TRUE)
  }
})

test_that("an enum or a yes or no in the form submits with one click", {
  ns <- shiny::NS("s")
  enum <- list(answer = ellmer::type_enum(c("Cone", "Cup")))
  boolean <- list(answer = ellmer::type_boolean())
  text <- list(answer = ellmer::type_string())
  step <- function(question, fixed = NULL) {
    as.character(form_step(
      ns,
      list(id = "a", text = "A?", fixed = fixed),
      question
    ))
  }

  for (html in c(step(enum, c("Cone", "Cup")), step(boolean))) {
    expect_match(html, 'data-pick="s-form_pick_a"', fixed = TRUE)
    expect_no_match(html, "s-form_next", fixed = TRUE)
  }
  expect_match(step(boolean), 'data-value="TRUE"', fixed = TRUE)
  expect_match(step(text), "s-form_next", fixed = TRUE)

  # An optional one-click question gets a Skip button
  optional <- step(list(answer = ellmer::type_boolean(required = FALSE)))
  expect_match(optional, 'id="s-form_next"', fixed = TRUE)
  expect_match(optional, ">Skip<", fixed = TRUE)
})

test_that("the class that hides the chat input exists in shinychat", {
  css_file <- list.files(
    system.file(package = "shinychat"),
    pattern = "^shinychat\\.css$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_length(css_file, 1)
  shinychat_css <- paste(
    readLines(css_file[[1]], warn = FALSE),
    collapse = "\n"
  )
  ours <- as.character(survey_complete("Done", "survey-chat"))

  expect_match(ours, "#survey-chat .shiny-chat-input", fixed = TRUE)
  expect_match(shinychat_css, "\\.shiny-chat-input(?![\\w-])", perl = TRUE)
})
