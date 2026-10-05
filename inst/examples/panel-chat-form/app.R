# Packages ----
library(surveychat)
library(ellmer)
library(shiny)
library(bslib)

# Survey ----
survey <- survey_spec(version = "1.1") |>
  set_config(views = c("chat", "form", "side_by_side")) |>
  set_messages(
    welcome = "Welcome to the AI Coding Workshop sign-up!",
    completion = prompt_llm(
      paste(
        "Write one short, casual sentence (under 20 words) that shows you",
        "heard this person, as a friend would. React to one specific thing",
        "they told us, such as their project or what they hope to learn.",
        "Do not summarize them, do not mention their role, and do not thank",
        "them or say goodbye."
      ),
      format = "{content}\n\nThanks, {name|friend}! See you at the workshop."
    )
  ) |>
  add_question(
    "name",
    text = "What's your first name?",
    answer = type_string(
      "The first name or nickname. Omit it if they decline to share one.",
      required = FALSE
    )
  ) |>
  add_question(
    "role",
    text = "Hey, {name|there}!\n\nWhat is your role?",
    answer = type_enum(
      c(
        "Student",
        "Data Scientist",
        "Software Engineer",
        "Researcher"
      ),
      "Their main role at work or school. Map a reply to the closest title"
    )
  ) |>
  add_question(
    "day",
    text = "Which days can you attend?",
    answer = type_array(
      type_enum(c(
        "Tuesday, November 3",
        "Thursday, November 5",
        "Saturday, November 7"
      )),
      "The workshop days they can attend"
    )
  ) |>
  add_question(
    "dinner",
    text = "Will you join us for dinner after the workshop?",
    answer = type_enum(
      c("Yes", "Maybe", "No"),
      "Whether they join the dinner. Map an unsure reply to Maybe"
    )
  ) |>
  add_question(
    "diet",
    text = "Any dietary needs we should know about?",
    answer = type_string(
      "Their dietary needs, such as vegetarian or no nuts, or 'No dietary needs'"
    ),
    choices = "No dietary needs",
    valid = "they named a dietary need or said they have none",
    when = ~ dinner %in% c("Yes", "Maybe")
  ) |>
  add_question(
    "goal",
    text = "What do you hope to learn at the workshop?",
    answer = type_string("The topic or skill they hope to learn"),
    valid = "they named a topic or skill"
  ) |>
  add_question(
    "experience",
    text = prompt_llm(
      paste(
        "A {role} hopes to learn {goal} at an AI coding workshop. Ask one",
        "short, open question about their experience with AI coding so far.",
        "Do not name any tools or list examples. Return only the question."
      )
    ),
    answer = type_string("Their experience with AI coding so far")
  ) |>
  add_question(
    "project",
    intro = prompt_llm(
      paste(
        "Write under 12 words to come before the next question. Their",
        "experience with AI coding: {experience|unknown}. If it is",
        "unknown, write a neutral transition that does not mention experience.",
        "Otherwise, acknowledge what they said plainly, like a person who",
        "listened. Do not praise or describe any tool, and do not ask a",
        "question."
      ),
      format = "{content}"
    ),
    text = prompt_llm(
      paste(
        "A {role} hopes to learn {goal} at an AI coding workshop. Ask one",
        "short, open question about a project or task where they want to use",
        "what they learn. Do not list examples. Return only the question."
      )
    ),
    answer = type_string("The project or task where they want to use it")
  ) |>
  add_question(
    "project_detail",
    text = prompt_llm(
      paste(
        "This person wants to work on {project|a project} after an AI coding",
        "workshop. Ask one short, curious follow-up question about the most",
        "interesting part of what they told us, as a friend would. Return",
        "only the question."
      )
    ),
    answer = type_string("Their answer to the follow-up question")
  )

# Backends ----
chat <- getOption("surveychat.example_chat")
if (is.null(chat)) {
  stop(
    "Start this app with surveychat::run_example(), which sets the chat.",
    call. = FALSE
  )
}
con <- DBI::dbConnect(RSQLite::SQLite(), "workshop.db")
onStop(\() DBI::dbDisconnect(con))

# Theme ----
theme <- bs_theme(
  version = 5,
  bg = "#f6f7fb",
  fg = "#1f2433",
  primary = "#4f5bd5",
  base_font = font_google("Inter", local = FALSE),
  heading_font = font_google("Inter", wght = 600, local = FALSE),
  "border-radius" = "0.75rem",
  "card-border-color" = "transparent",
  "card-bg" = "#ffffff"
) |>
  bs_add_rules(
    "
    .survey-shell {
      max-width: 640px; height: calc(100vh - 11rem); margin-bottom: 2rem;
      transition: max-width .3s ease;
    }
    .survey-shell:has(.sb-view-pick input[value='side_by_side']:checked) {
      max-width: 1100px;
    }
    .survey-shell .card { box-shadow: 0 8px 28px rgba(31, 36, 51, .08); }
    .survey-shell .card-header {
      background: $primary; color: #fff; font-weight: 600;
    }
    .survey-shell .card-header .sb-progress-label { color: rgba(255,255,255,.85); }
    .survey-shell .card-header .sb-progress-track { background: rgba(255,255,255,.3); }
    .survey-shell .card-header .sb-progress-fill { background: #fff; }
    "
  )

# App ----
ui <- page_fixed(
  title = "Workshop sign-up",
  theme = theme,
  div(
    class = "text-center mt-5 mb-4",
    h1(class = "h3 mb-1", "AI Coding Workshop"),
    p(
      class = "text-body-secondary mb-0",
      "Sign up in the form, the AI chat, or both."
    )
  ),
  as_fill_carrier(div(
    class = "survey-shell mx-auto",
    survey_panel_ui("survey")
  ))
)

server <- function(input, output, session) {
  survey_server("survey", survey, chat, con)
}

shinyApp(ui, server)
