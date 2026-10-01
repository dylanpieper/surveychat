# Packages ----
library(surveychat)
library(ellmer)
library(shiny)
library(bslib)

# Survey ----
survey <- survey_spec(version = "1.0") |>
  set_config(methods = c("form", "chat")) |>
  set_messages(
    welcome = "Thanks for taking part. Six short questions about you.",
    completion = "Thank you! Your answers are recorded."
  ) |>
  add_question(
    "age",
    text = "How old are you?",
    answer = type_integer("The age in whole years"),
    valid = "they gave a plausible age from 13 to 120"
  ) |>
  add_question(
    "gender",
    text = "What is your gender?",
    answer = type_string(
      "The gender in their own words, or 'Prefer not to say'"
    ),
    choices = c("Woman", "Man", "Non-binary", "Prefer not to say")
  ) |>
  add_question(
    "country",
    text = "In which country do you live?",
    answer = type_string("The country name in English"),
    valid = "they named a country or a territory"
  ) |>
  add_question(
    "education",
    text = "What is the highest level of education that you completed?",
    answer = type_enum(
      c(
        "Less than secondary school",
        "Secondary school",
        "Vocational or trade school",
        "Bachelor's degree",
        "Master's degree",
        "Doctorate"
      ),
      "The highest level of education completed"
    )
  ) |>
  add_question(
    "employment",
    text = "What is your employment status?",
    answer = type_enum(
      c(
        "Employed full time",
        "Employed part time",
        "Self-employed",
        "Student",
        "Not employed",
        "Retired"
      ),
      "The current employment status"
    )
  ) |>
  add_question(
    "role_detail",
    text = prompt_llm(
      paste(
        "The person's employment status is {employment}. Ask one short,",
        "neutral question about their main role or daily activity."
      )
    ),
    answer = type_string("Their main role or daily activity")
  )

# Backends ----
chat <- getOption("surveychat.example_chat")
if (is.null(chat)) {
  stop(
    "Start this app with surveychat::run_example(), which sets the chat.",
    call. = FALSE
  )
}
con <- DBI::dbConnect(RSQLite::SQLite(), "demographics.db")
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
    .survey-shell:has(.sb-view-pick input[value='both']:checked) {
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
  title = "About you",
  theme = theme,
  div(
    class = "text-center mt-5 mb-4",
    h1(class = "h3 mb-1", "Tell us about you"),
    p(
      class = "text-body-secondary mb-0",
      "Use the form, the AI chat, or both side by side."
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
