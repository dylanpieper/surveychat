# Simulated typing for bot messages

# Async generator that yields `message` one character at a time. Each delay
# is `character_delay` plus a random offset within `delay_variance`.
bot_response <- coro::async_generator(function(
  message,
  response_delay = 0,
  character_delay = 0.02,
  delay_variance = 0.01
) {
  await(coro::async_sleep(response_delay))
  chars <- strsplit(as.character(message), "", useBytes = FALSE)[[1]]
  for (char in chars) {
    # Add randomness to typing delay
    random_delay <- character_delay +
      stats::runif(1, -delay_variance, delay_variance)
    random_delay <- max(0.005, random_delay) # Ensure minimum delay
    yield(char)
    await(coro::async_sleep(random_delay))
  }
})
