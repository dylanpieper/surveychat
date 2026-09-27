# Create the survey schema on a connection

Makes the `sessions` and `responses` tables and their indexes. It is
safe to call on every start, because it leaves existing tables alone.
[`survey_server()`](https://dylanpieper.github.io/surveychat/reference/survey_server.md)
calls it for you; call it yourself to make the tables before the first
user arrives.

## Usage

``` r
init_database(con, quiet = FALSE)
```

## Arguments

- con:

  A connection from any DBI driver, or a
  [`pool::dbPool()`](http://rstudio.github.io/pool/reference/dbPool.md).

- quiet:

  If `TRUE`, show no message when the tables are made.

## Value

`con`, invisibly.

## Examples

``` r
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
init_database(con)
#> ✔ Survey schema created on "SQLiteConnection"
DBI::dbListTables(con)
#> [1] "responses"       "sessions"        "sqlite_sequence"
DBI::dbDisconnect(con)
```
