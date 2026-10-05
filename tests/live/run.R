# Runs the live model checks in this folder against Claude Haiku. Start it
# from the package root: Rscript tests/live/run.R
devtools::load_all(quiet = TRUE)
testthat::test_dir(
  "tests/live",
  reporter = "summary",
  load_package = "none",
  stop_on_failure = TRUE
)
