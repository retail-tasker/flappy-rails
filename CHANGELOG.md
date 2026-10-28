# Changelog

## Unreleased

- `calm: true` on `flappy_pipe` and `flappy_capybara` keeps the pipe on clear skies
  through setup, and `flappy_weather!` starts the level when the test is ready. A calm
  pipe that never gets its weather fails the test in teardown, so a forgotten call
  cannot pass on clear skies. `flappy_weather!(pipe)` starts one pipe.

## 0.1.1

- Resets are now rolled once per connection, not once per chunk of data. A big page
  load is no longer cut just for being big. Built-in levels were retuned to match.
- A small HTTP control panel (`flappy pipe --control PORT`, or `control:` in Ruby) so a
  test in any language can sign in on clear skies and then switch the weather.
- `Pipe#play(level)` and `Pipe#stop_level`.

## 0.1.0

First flight.

- `Flappy::Pipe`: a TCP proxy with latency, jitter, upload and download speed caps,
  random connection resets, stalls and offline.
- `Flappy::Level` and six built-in levels, from Warm-Up Wobble to The Lift.
- `flappy run`: run a command repeatedly, level by level, with a scoreboard.
- `flappy pipe`: run a pipe from the command line.
- `Flappy::Minitest` with `flappy_pipe` and `flappy_capybara` for Rails tests.
