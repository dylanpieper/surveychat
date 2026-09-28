# Simulated typing for bot messages

# Async generator that types the first part of `message` one character at a
# time, then adds each later part whole, after a blank line. Later parts are
# ready content, such as suggestion cards, so they do not look generated.
# Each delay is `character_delay` plus a random offset within
# `delay_variance`.
bot_response <- coro::async_generator(function(
  message,
  response_delay = 0,
  character_delay = 0.02,
  delay_variance = 0.01
) {
  await(coro::async_sleep(response_delay))
  message <- as.character(message)
  chars <- strsplit(message[1], "", useBytes = FALSE)[[1]]
  for (char in chars) {
    # Add randomness to typing delay
    random_delay <- character_delay +
      stats::runif(1, -delay_variance, delay_variance)
    random_delay <- max(0.005, random_delay) # Ensure minimum delay
    yield(char)
    await(coro::async_sleep(random_delay))
  }
  for (part in message[-1]) {
    yield(paste0("\n\n", part))
  }
})
