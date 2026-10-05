# Survey data

surveychat writes every survey to two SQL tables on any DBI connection.
This article describes the tables, the data dictionary, and how to read
the answers.

## Tables

**`sessions`**: one row for each user.

| Column | Meaning |
|----|----|
| `session_id` | Generated key |
| `started_at`, `completed_at` | Times of the start and the completion |
| `completed` | `TRUE` after the last answer |
| `retry_count` | Total retries in the session |
| `version` | The version of the question set, from [`survey_spec()`](https://dylanpieper.github.io/surveychat/reference/survey_spec.md) or [`set_config()`](https://dylanpieper.github.io/surveychat/reference/set_config.md) |
| `duration_seconds` | Time since the start, updated after each answer |
| `methods` | The answer methods that the views offer, such as `form,chat`, from `set_config(views = )` |

**`responses`**: one row for each answer, including each retry.

| Group    | Columns                                                      |
|----------|--------------------------------------------------------------|
| Keys     | `response_id`, `session_id`, `question_id`, `question_order` |
| Exchange | `question_text`, `answer_raw`, `answer_extracted`            |
| Quality  | `valid`, `retry_attempt`, `method` (`chat` or `form`)        |
| Timing   | `responded_at`, `duration_seconds`                           |

An answer that came early, in the reply to an earlier question, has no
`question_text`. A skipped optional answer has no `answer_extracted`. A
form answer has no `valid` flag when the LLM validation failed. A
question that its `when` rule skips has no row.

The schema is fixed.
[`inst/data-dict.yaml`](https://github.com/dylanpieper/surveychat/blob/main/inst/data-dict.yaml)
describes each table and column in the
[data-dict](https://data-dict.tidyverse.org/) format, and the package
installs it at `system.file("data-dict.yaml", package = "surveychat")`.
To use your own table or column names, make views or copy the data on
your side.

## Read the answers

The tables are plain SQL, so any DBI client can read them:

``` r

con <- DBI::dbConnect(RSQLite::SQLite(), "survey.db")
sessions <- DBI::dbReadTable(con, "sessions")
responses <- DBI::dbReadTable(con, "responses")
DBI::dbDisconnect(con)
```

## Databases

[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
takes any DBI connection or a
[`pool::dbPool()`](http://rstudio.github.io/pool/reference/dbPool.md).
The package supports:

- SQLite
- DuckDB
- Postgres
- MySQL and MariaDB

Every statement uses DBI primitives, so the same code runs on each
backend. The differences that are left are in `R/dialect.R`, with one
entry for each driver class:

- The declaration of an auto-incrementing key
- Support for a foreign key
- Support for `INSERT ... RETURNING`
- The query for the last generated ID

A driver with no entry gets ANSI defaults. To add a backend, add an
entry to `R/dialect.R`.
