#' Application configuration

#' Default survey configuration
#' @param db_path Database file path
#' @param db_driver Database driver expression
#' @param tries Maximum retry attempts for unclear responses
#' @param response_delay Delay before bot response (seconds)
#' @param character_delay Delay between characters in streaming (seconds)
#' @param delay_variance Randomness factor for character delay (seconds)
#' @param version Survey version
#' @return Configuration list
#' @export
default_config <- \(db_path = "survey.db",
                    db_driver = rlang::expr(RSQLite::SQLite()),
                    tries = 2,
                    response_delay = 0,
                    character_delay = 0.02,
                    delay_variance = 0.01,
                    version = "1.0") {
  list(
    db_path = db_path,
    db_driver = db_driver,
    tries = tries,
    response_delay = response_delay,
    character_delay = character_delay,
    delay_variance = delay_variance,
    version = version
  )
}
