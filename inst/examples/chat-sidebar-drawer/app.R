# Packages ----
library(surveychat)
library(ellmer)
library(shiny)
library(bslib)

# Menu ----
flavors <- list(
  list("Millie's Mint", "Cool mint with dark chocolate flakes.", "🌿"),
  list("Carmen's Caramel", "Burnt sugar, sea salt, and cream.", "🍯"),
  list("Sam's Strawberry", "Fresh berries from the farm down the road.", "🍓"),
  list("Dylan's Dough", "Brown sugar dough in vanilla bean.", "🍪")
)
menu <- paste(
  vapply(flavors, \(flavor) flavor[[1]], character(1)),
  collapse = ", "
)

# Survey ----
survey <- survey_spec(version = "1.1") |>
  set_messages(
    welcome = "Hi, I'm RoboScoop! 🍨",
    retry = "Sorry, I had trouble understanding that. 🤔 Could you try again?",
    completion = paste(
      "Thanks, {name|friend}! Your scoop card is ready. 🍦✨"
    ),
    closed = "Survey complete. Thank you!"
  ) |>
  add_question(
    "name",
    text = "Who do I have the pleasure of talking to? We might name our next batch after you!",
    answer = type_string(
      paste(
        "The first name or nickname the person gave, e.g. 'Dylan' from",
        "'I'm Dylan Pieper' or 'Dyl' from 'call me dyl'. Omit this field only",
        "if they decline to share a name."
      ),
      required = FALSE
    ),
    choices = "I'd rather stay anonymous",
    valid = paste(
      "they gave a plausible name or nickname, or they declined to share one",
      "(e.g. 'skip', 'pass', 'no thanks', 'rather stay anonymous'); random",
      "keyboard text is not valid"
    )
  ) |>
  add_question(
    "ice_cream",
    text = "Hey {name|there}! What's your favorite ice cream flavor? 🍦",
    answer = type_string("The ice cream flavor, e.g. 'mint chocolate chip'"),
    valid = "they mentioned any flavor"
  ) |>
  add_question(
    "served",
    text = "How do you like your {ice_cream} served?",
    answer = type_enum(
      c("Cone", "Cup", "Waffle bowl", "Sundae", "Milkshake", "Mixer"),
      paste(
        "How they like their ice cream served. Mixer means ice cream blended",
        "with mix-ins, like a concrete or a Blizzard"
      )
    ),
    valid = "they picked one of the options or described one of them"
  ) |>
  add_question(
    "topping",
    text = "Do you add anything to your {ice_cream}, or keep it plain?",
    answer = type_string(
      "The topping or mix-in they add, or 'none' if they keep it plain"
    ),
    choices = list(
      prompt_llm(paste(
        "Suggest exactly 2 common toppings for {ice_cream} ice cream served",
        "as a {served}. If it is a Mixer, suggest mix-ins instead. Use 1 to 3",
        "words each."
      )),
      "Keep it plain"
    ),
    valid = "they named a topping or mix-in, or said they keep it plain"
  ) |>
  add_question(
    "visits",
    text = "How often do you stop by Scoops & Co?",
    intro = prompt_llm(
      paste(
        "Share one short, well-known fun fact about how {ice_cream} was",
        "invented or became popular. You can pick one part of it, such as its",
        "base (e.g. frozen custard) or its main mix-in (e.g. cookies). Do not",
        "invent names, dates, or places; if you are not sure, keep the fact",
        "general. Use 1 or 2 sentences with no prefix, and add one fun emoji",
        "(not an ice cream cone or dish)."
      ),
      format = "Fun fact: {content}"
    ),
    answer = type_enum(
      c(
        "This is my first time",
        "About once a week",
        "A few times a month",
        "About once a month",
        "A few times a year"
      ),
      paste(
        "How often they visit the shop. Map a vague answer to the closest",
        "choice, e.g. 'I'm a regular' to 'About once a week'"
      )
    ),
    valid = "they gave any sense of how often they visit"
  ) |>
  add_question(
    "new_flavor",
    text = prompt_llm(paste(
      "A customer's favorite ice cream flavor is {ice_cream}. Our shop makes",
      paste0("only these flavors now: ", menu, "."),
      "If their favorite is not on that list, it comes from another shop, so",
      "never call it ours or imply that we make it.",
      "Our shop churns one new flavor each week. Write one short, friendly",
      "question about which flavor they would like us to make next week,",
      "and follow the pattern that fits:",
      "If their favorite is NOT on our list, ask if we should make it, or if",
      "there is another flavor they would like to see, e.g. 'Would you like",
      "us to make Oreo custard next week, or is there another flavor you'd",
      "love to see?'",
      "If their favorite IS on our list, say we already make it and ask for",
      "another flavor, e.g. 'Good news, we already make Sam's Strawberry! What",
      "other flavor would you love to see us make next week?'",
      "Match by flavor, so 'strawberry' matches 'Sam's Strawberry', and use",
      "the full name from our list in your reply.",
      "Do not list other flavors or examples, and do not ask how they serve",
      "it, about add-ons, or about flavor profiles.",
      "Return ONLY the question text."
    )),
    answer = type_string(paste(
      "The flavor they want the shop to make next. If they say yes or point",
      "to their favorite (e.g. 'that one' or 'you don't have it'), use their",
      "favorite flavor from the question."
    )),
    valid = paste(
      "they named a flavor, said yes to their favorite, or pointed to their",
      "favorite, even as a complaint that we don't make it"
    )
  ) |>
  add_question(
    "club",
    text = "Want to join our flavor club? Members get a free scoop on their birthday. 🎂",
    answer = type_boolean("Whether they join the flavor club")
  ) |>
  add_question(
    "birthday",
    text = "Sweet! What's your date of birth?",
    answer = type_string("Their date of birth"),
    input = "date",
    when = ~club
  )

# Scoop card ----
labels <- c(
  name = "Name",
  ice_cream = "Flavor",
  served = "Served",
  topping = "Add-ons",
  visits = "Visits",
  new_flavor = "Next flavor",
  club = "Flavor club",
  birthday = "Birthday"
)

# A yes or no answer shows as words
scoop_value <- function(value) {
  if (is.logical(value)) {
    if (isTRUE(value)) "Yes" else "No"
  } else {
    value
  }
}

scoop_card <- function(answers, complete) {
  rows <- lapply(intersect(names(labels), names(answers)), \(id) {
    tags$li(
      class = "list-group-item d-flex justify-content-between gap-3 px-0",
      tags$span(class = "text-body-secondary", labels[[id]]),
      tags$strong(class = "text-end", scoop_value(answers[[id]]))
    )
  })
  tagList(
    tags$p(
      class = "small text-body-secondary",
      if (complete) {
        "All set! Our kitchen will read your answers."
      } else {
        "Your answers so far. They help us pick the next batch."
      }
    ),
    tags$ul(class = "list-group list-group-flush", rows)
  )
}

# Shop page ----
steps <- list(
  list("1", "Tell us your favorites", "A short chat about what you love."),
  list("2", "We churn the top picks", "Our kitchen reads every answer."),
  list("3", "Taste the new batch", "Find it in the case next week.")
)

step_card <- function(step) {
  tags$div(
    class = "text-center px-3",
    tags$div(class = "step-number mx-auto mb-3", step[[1]]),
    tags$h3(class = "h5", step[[2]]),
    tags$p(class = "text-body-secondary mb-0", step[[3]])
  )
}

flavor_card <- function(flavor) {
  card(
    class = "flavor-card border-0 shadow-sm",
    card_body(
      class = "text-center py-4",
      tags$div(class = "display-5", flavor[[3]]),
      tags$h3(class = "h5 mt-3", flavor[[1]]),
      tags$p(class = "text-body-secondary small mb-0", flavor[[2]])
    )
  )
}

theme <- bs_theme(
  version = 5,
  primary = "#b0305c",
  bg = "#fffaf6",
  fg = "#2d1f1a",
  base_font = font_google("Inter"),
  heading_font = font_google("Fraunces"),
  "border-radius" = "0.75rem"
) |>
  bs_add_rules(
    "
    .hero { max-width: 44rem; }
    .eyebrow { letter-spacing: .12em; text-transform: uppercase; }
    .step-number {
      width: 2.5rem; height: 2.5rem; border-radius: 50%;
      display: grid; place-items: center; font-weight: 700;
      color: var(--bs-primary);
      background: rgba(var(--bs-primary-rgb), .1);
    }
    .flavor-card { transition: transform .15s ease; }
    .flavor-card:hover { transform: translateY(-3px); }
    "
  )

# Backends ----
chat <- getOption("surveychat.example_chat")
if (is.null(chat)) {
  stop(
    "Start this app with surveychat::run_example(), which sets the chat.",
    call. = FALSE
  )
}
con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
onStop(\() DBI::dbDisconnect(con))

# App ----
ui <- page_sidebar(
  title = "Scoops & Co 🍦",
  theme = theme,
  fillable = FALSE,
  sidebar = sidebar(
    id = "survey_sidebar",
    title = NULL,
    position = "right",
    fillable = TRUE,
    open = "closed",
    width = 480,
    survey_chat_ui(
      "survey",
      drawer = shinychat::chat_drawer(
        title = "Your scoop card",
        open = FALSE,
        width = 240
      )
    )
  ),
  tags$section(
    class = "hero mx-auto text-center py-5",
    tags$p(
      class = "eyebrow small fw-semibold text-primary mb-3",
      "Small-batch ice cream since 1996"
    ),
    tags$h1(class = "display-4 fw-bold mb-3", "You pick our next batch."),
    tags$p(
      class = "lead text-body-secondary mb-4",
      "Every week we churn one new flavor. This week, you decide. ",
      "Take our two-minute flavor survey, and your answers go straight ",
      "to our kitchen."
    ),
    actionButton(
      "open_survey",
      "Take the flavor survey",
      icon = icon("ice-cream"),
      class = "btn-primary btn-lg px-5 py-3 rounded-pill shadow-sm"
    )
  ),
  tags$section(
    class = "py-5 border-top",
    tags$h2(class = "h3 text-center mb-5", "How your answers shape the menu"),
    layout_column_wrap(width = "220px", !!!lapply(steps, step_card))
  ),
  tags$section(
    class = "py-5 border-top",
    tags$h2(class = "h3 text-center mb-2", "Now scooping"),
    tags$p(
      class = "text-center text-body-secondary mb-5",
      "Four flavors made this morning on Main Street."
    ),
    layout_column_wrap(width = "200px", !!!lapply(flavors, flavor_card))
  )
)

server <- function(input, output, session) {
  observeEvent(input$open_survey, {
    toggle_sidebar("survey_sidebar", open = TRUE)
  })
  survey_server("survey", survey, chat, con, drawer = scoop_card)
}

shinyApp(ui, server)
