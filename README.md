# surveybot

surveybot collects data in a conversation with [shinychat](https://posit-dev.github.io/shinychat/). The user answers structured questions in a natural dialogue. At the same time, the LLM extracts the data, generates content, and asks adaptive questions.

## Usage 🍦✨

``` r
renv::restore()
shiny::runApp("app.R")
```

Set an API key for your LLM provider. The demo uses `ellmer::chat_claude()`, which reads `ANTHROPIC_API_KEY`. To use a different provider, swap in another `ellmer` chat function in `app.R`.

The demo collects the ice cream preferences of the user. The files are modular, and you can make your own surveybot from them.

## Key Features

-   **LLM extraction** with structured schemas that validate and retry unclear answers
-   **Adaptive questions** that the LLM writes from the last answer of the user
-   **Generated content** woven into a fixed question
-   **SQL storage** of raw and extracted answers, retry counts, and timings on any DBI driver
-   **Chat UI** with simulated typing, a progress cue, and a closing message

## Programming Patterns

### Declarative Surveys

`app.R` contains data only. A survey has three lists: `questions`, `messages`, and `content`. The application sends these lists to `chat_survey()`. To make a different surveybot, modify the lists.

``` r
list(
  id = "ice_cream",                                    # The response field and the database column name
  text = "Hey {name}! What's your favorite flavor?",   # The app fills {placeholders} from previous answers
  content = "funfact",                                 # An optional content template
  schema = type_object(                                # The ellmer extraction schema
    ice_cream = type_string("The ice cream flavor"),
    answered_clearly = type_boolean("TRUE if they mentioned any flavor")
  )
)
```

### Extraction as Validation

Each schema has an answer field and an `answered_clearly` flag. One LLM call extracts the answer and also rates the answer. Therefore, the application does not need a second step for the validation, and it does not need a regular expression.

If the flag is `FALSE`, the survey asks the question again. The maximum number of retries is `config$tries`. After the last retry, the survey keeps the unclear answer and continues to the next question. The user cannot stop the survey with a bad answer.

### Template Interpolation

The questions, the prompts, and the messages use the same `{placeholder}` syntax. The application replaces each placeholder with a value from the previous answers. There are two functions:

-   `interpolate()` replaces the placeholder with the value.
-   `interpolate_with_context()` also makes the first letter uppercase if the value starts a sentence.

If a value is not available, the application writes the name of the variable. It does not stop with an error.

The prompt also declares the data that it needs. `extract_variables()` reads the prompt and finds the `{names}`. Then the application gets only these fields from the responses. If you add `{brand_shop}` to a prompt, the application supplies the data automatically.

### Content Templates

A `content` entry has a `prompt` and an optional `intro`. If the entry has an `intro`, the application puts the generated text before the next question:

``` r
funfact = list(
  prompt = "Share a fun fact about {ice_cream} ice cream.",
  intro = "Oh, {ice_cream}! {content}\n\n{next_question}"
)
```

If the entry does not have an `intro`, the generated text becomes the question. This is the adaptive branch, and the LLM writes the question from the last answer of the user. The question that uses the template sets `text = NULL`:

``` r
# Content templates ----
follow_up = list(
  prompt = paste(
    "User '{name}' likes {ice_cream} ice cream because: {why_favorite}.",
    "Acknowledge their reason briefly. Then, generate one curious follow-up question",
    "about their ice cream preference based on what they said.",
    "Return ONLY the question text with no preamble."
  )
)

# Survey questions ----
list(
  id = "fu_favorite",
  text = NULL,
  content = "follow_up",
  schema = type_object(
    fu_favorite = type_string("The core answer to the adaptive question"),
    answered_clearly = type_boolean("TRUE if they engaged with the question")
  )
)
```

The application supplies `{name}`, `{ice_cream}`, and `{why_favorite}` from the previous answers. The reply of the LLM becomes the question that the user sees. The application keeps this text in the `question_text` of the response, because the text is different for each user.

If the generation fails, the application skips the adaptive question and continues with the next fixed question.

### Portable SQL

`app.R` opens the connection and passes it to `chat_survey()`, thus every driver argument stays in one place:

``` r
con <- dbConnect(RSQLite::SQLite(), "survey.db")
onStop(\() dbDisconnect(con))

# Or any other driver:
#   dbConnect(duckdb::duckdb(), "survey.duckdb")
#   dbConnect(RPostgres::Postgres(), host = "localhost", dbname = "survey")
```

`R/db.R` builds every statement from DBI primitives, thus the same code runs on each backend. `R/dialect.R` holds the differences that are left: how a driver declares an auto-incrementing key, whether it accepts a foreign key, whether it has `INSERT ... RETURNING`, and how it reports the last generated id. The application matches an entry on the class of the connection, and a driver without an entry gets the ANSI defaults.

The application supports SQLite, DuckDB, Postgres, and MySQL/MariaDB. Add other backends to `R/dialect.R`.

### Configuration

`default_config()` holds the rest of the parameters:

-   `tries`: The maximum number of retries for an unclear answer.
-   `character_delay` and `delay_variance`: The speed of the simulated typing. Use `character_delay = 0` for no delay.
-   `response_delay`: The delay before the bot starts a message.
-   `version`: The version of the question set, which the application writes to each session.

``` r
chat_survey(
  input, output, session, chat, con, questions, messages, content,
  config = default_config(tries = 3, character_delay = 0)
)
```

## Data Model

The table `sessions` has one record for each user. The record has the times of the start and the completion, the flag `completed`, the total `retry_count`, the `question_set_version`, and the `duration_seconds`.

The table `responses` has one record for each answer. Each record refers to a session and includes the `question_id`, the `question_order`, the `question_text` that the application showed, the `input_raw`, the `input_extracted`, the flag `answered_clearly`, the `retry_attempt`, and the `question_duration_seconds`. The text of an adaptive question is different for each user, thus the application keeps it with the answer.

The application keeps the raw input and the extracted input. Therefore, you can examine the quality of the extraction after the survey. The indexes cover the queries by session, by question, and by order.

The application creates the schema on the connection at the start of a session, and it leaves an existing schema alone. Thus you can also create the tables yourself with `db$init_database(con)`.

``` r
source("analyze.R")
```
