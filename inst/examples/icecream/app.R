# Packages ----
library(surveychat)
library(ellmer)
library(shiny)

# Survey ----
survey <- survey_spec(version = "1.0") |>
  set_messages(
    welcome = "Hello! I'd love to learn about your ice cream preferences. 🍨",
    retry = "Sorry, I had trouble understanding that. 🤔 Could you try again?",
    completion = paste(
      "Thanks, {name}! I recorded your love for {ice_cream}! 🤓📊",
      "I hope you enjoy your next scoop soon! 🍦✨"
    ),
    closed = "Survey complete. Thank you!"
  ) |>
  add_question(
    "name",
    text = "What's your name?",
    answer = type_string(
      "Just the person's first name, e.g. 'Dylan' from 'call me dylan' or 'Dylan Pieper'"
    ),
    valid = "they gave a reasonable first and/or last name, not only a nickname"
  ) |>
  add_question(
    "ice_cream",
    text = "Hey {name}! Let's talk ice cream. 🍦 What's your favorite flavor?",
    answer = type_string("The ice cream flavor, e.g. 'mint chocolate chip'"),
    valid = "they mentioned any flavor"
  ) |>
  add_question(
    "why_favorite",
    text = "What about {ice_cream} makes it your favorite ice cream flavor?",
    intro = prompt_llm(
      paste(
        "Share a fun fact about {ice_cream} ice cream.",
        "Return a brief fun fact (1-2 sentences) with no prefix and include",
        "a fun emoji (but don't use the ice cream cone or dish)."
      ),
      format = "Oh, {ice_cream}! {content}"
    ),
    answer = type_string("The reason why they like this preference"),
    valid = paste(
      "they mentioned ANY positive feeling, emotion, memory, or reason related",
      "to their preference, even if very brief like 'I love it'"
    )
  ) |>
  add_question(
    "fu_favorite",
    text = prompt_llm(paste(
      "User '{name}' likes {ice_cream} ice cream because: {why_favorite}.",
      "Acknowledge their reason briefly. Then, generate one curious follow-up question",
      "about their ice cream preference based on what they said.",
      "Examples: If they mention texture, ask about their experience or if they add extra toppings.",
      "If they mentioned nostalgia, ask about memories.",
      "Return ONLY the question text with no preamble."
    )),
    answer = type_string("The core answer to the adaptive question")
  ) |>
  add_question(
    "brand_shop",
    text = "Love it! Where's your go-to spot to get {ice_cream} ice cream? 👀",
    answer = type_string(paste(
      "Brand or shop name EXACTLY as stated by user, no inference.",
      "If vague like 'the store', extract that literally"
    )),
    valid = paste(
      "they named a specific brand, shop, or location,",
      "not a vague place like 'the store' or 'somewhere'"
    )
  ) |>
  add_question(
    "when_eat",
    text = "{brand_shop} is a great choice! When do you crave {ice_cream} the most? 🤔",
    answer = type_string(
      "Brief summary of when they consume/enjoy their preference"
    ),
    valid = paste(
      "they described any timing, occasion, situation, or context for enjoying",
      "their preference, even if somewhat vague or unconventional"
    )
  )

# Backends ----
# Swap in any ellmer chat function to use a different provider, and any DBI
# driver or pool::dbPool() to use a different database.
chat <- chat_claude(model = "claude-haiku-4-5-20251001", echo = "none")
con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
onStop(\() DBI::dbDisconnect(con))

# App ----
ui <- survey_ui("survey", title = "SurveyChat")
server <- function(input, output, session) {
  survey_server("survey", survey, chat, con)
}

shinyApp(ui, server)
