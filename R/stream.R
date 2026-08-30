#' Simulated typing for bot messages

box::use(
  coro[async_generator, async_sleep, await, yield],
)

#' Create streaming bot response generator
#' @param message Message to stream
#' @param response_delay Initial delay before streaming (default 0)
#' @param character_delay Base delay between characters (default 0.02)
#' @param delay_variance Randomness factor for character delay (default 0.01)
#' @return Async generator
#' @export
bot_response <- async_generator(function(message,
                                         response_delay = 0,
                                         character_delay = 0.02,
                                         delay_variance = 0.01) {
  await(async_sleep(response_delay))
  chars <- strsplit(as.character(message), "", useBytes = FALSE)[[1]]
  for (char in chars) {
    # Add randomness to typing delay
    random_delay <- character_delay +
      stats::runif(1, -delay_variance, delay_variance)
    random_delay <- max(0.005, random_delay) # Ensure minimum delay
    yield(char)
    await(async_sleep(random_delay))
  }
})
