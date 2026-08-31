library(DBI)
library(RSQLite)
library(tidyverse)

# Connect to database ----
con <- dbConnect(RSQLite::SQLite(), "survey.db")

# Basic queries ----

# View all sessions
sessions <- dbReadTable(con, "sessions") |> as_tibble()
print(sessions)

# View all responses
responses <- dbReadTable(con, "responses") |> as_tibble()
print(responses)
