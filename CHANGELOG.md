# Changelog

## 0.1.0

First flight.

- `Flappy::Pipe`: a TCP proxy with latency, jitter, upload and download speed caps,
  random connection resets, stalls and offline.
- `Flappy::Level` and six built-in levels, from Warm-Up Wobble to The Lift.
- `flappy run`: run a command repeatedly, level by level, with a scoreboard.
- `flappy pipe`: run a pipe from the command line.
- `Flappy::Minitest` with `flappy_pipe` and `flappy_capybara` for Rails tests.
