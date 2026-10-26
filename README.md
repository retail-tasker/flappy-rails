# Flappy Rails

Can your test suite make it through the pipes?

<p align="center">
  <img src="assets/flappy-rails.svg" alt="Flappy Rails: a small bird flying through green pipes above a railway track" width="100%">
</p>

Flappy Rails puts a pipe between your tests and your app. The pipe drops,
delays, throttles and flaps the connection on a loop. Run your suite against it
level by level, a hundred times if you like, and see how far it flies.

Real users are not on office wifi. They are in a lift, in a store with one bar,
or driving through a dead zone. Your tests passed on a perfect network, so
nobody knows what happens on the other kind. Now you can find out before they do.

Pure Ruby. No dependencies.

## Install

```ruby
# Gemfile
group :test do
  gem "flappy-rails"
end
```

## Quick start

Put a pipe in front of any host and port, and send your traffic through it.

```ruby
require "flappy/minitest"

class CheckoutTest < ActiveSupport::TestCase
  include Flappy::Minitest

  test "checkout survives a flaky connection" do
    pipe = flappy_pipe(to: "127.0.0.1:3000")
    response = Net::HTTP.get(URI("#{pipe.url}/checkout"))
    assert_match "Thanks for your order", response
  end
end
```

Run it normally and the pipe is clear skies, so the test behaves like any other.
Run it through the gauntlet (below) and the pipe plays a level while the test runs.

### Rails system tests

Put the pipe between the browser and the Capybara server:

```ruby
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Flappy::Minitest

  setup { flappy_capybara }
end
```

Every `visit` now goes through the pipe.

## The gauntlet

```
flappy run --times 100 -- bin/rails test test/system
```

This runs your command 100 times on every level. Each level plays its weather
while your tests run. A level is cleared when every run survives.

```
LEVEL 1: Warm-Up Wobble
  A little shaky, nothing a retry won't fix.
  ....  4/4 survived

LEVEL 3: The Tunnel
  20 seconds of signal, 5 seconds of nothing, on repeat.
  xxxx  0/4 survived
  logs for crashed runs: tmp/flappy

SCOREBOARD
  1  Warm-Up Wobble     4/4    cleared
  2  Pothole Pass       4/4    cleared
  3  The Tunnel         0/4    CRASHED

  Final score: 2 of 6 levels cleared.
  Down at level 3: The Tunnel. Start with the logs.
```

The output of every crashed run is saved so you can see what broke.

| Level | Name | What it does |
| --- | --- | --- |
| 1 | Warm-Up Wobble | A little latency and jitter. |
| 2 | Pothole Pass | Slow roads, and the odd connection dies. |
| 3 | The Tunnel | 20 seconds of signal, 5 seconds offline, on repeat. |
| 4 | Dead Zone | Connected on paper, but nothing moves for 15 seconds at a time. |
| 5 | Rural Run | One bar. Slow uploads, slow downloads, dropped connections. |
| 6 | The Lift (boss) | Signal, offline, stuck, crawling. Every few seconds. |

Options for `flappy run`:

```
--levels 1,3,the_lift   pick levels by number or name
--times N               runs per level (default 10)
--speed X               play the weather X times faster, handy for short suites
--seed N                repeatable randomness
--sudden-death          stop at the first level that crashes
--pass-rate 0.95        let the odd run crash
--verbose               print every run's output
```

The exit code is 0 when every level is cleared, so it works in CI.

## Make your own level

A level is a loop of phases. Each phase sets the weather for some seconds.

```ruby
level = Flappy::Level.new(
  name: :train_to_work,
  title: "The 7:42 to Central",
  tagline: "Good until the river, then nothing.",
  phases: [
    Flappy::Level.phase(40, "city"),
    Flappy::Level.phase(8, "river", offline: true),
    Flappy::Level.phase(12, "suburbs", latency: 400, up_kbps: 64)
  ]
)

pipe = Flappy.pipe(to: "127.0.0.1:3000")
player = level.play(pipe)
# ... run your checks ...
player.stop
```

You can also set the weather by hand:

```ruby
pipe.conditions = Flappy::Conditions.new(latency: 300, jitter: 200, up_kbps: 64)
pipe.offline!        # cuts connections in flight and refuses new ones
pipe.stall!          # holds everything until you clear it
pipe.clear!
pipe.under(Flappy::Conditions.new(offline: true)) { ... }
```

| Condition | What it does |
| --- | --- |
| `latency`, `jitter` | Milliseconds added each time traffic starts moving, plus a random extra. |
| `up_kbps`, `down_kbps` | Speed caps for uploads and downloads. |
| `reset_chance` | Chance (0.0 to 1.0) that a new connection is cut dead a moment after it opens. |
| `stall` | Hold all traffic, and new connections, until it clears. |
| `offline` | Refuse new connections and cut the ones in flight. |

## A pipe on its own

You can run a pipe from the command line in front of anything, and point any
client at it.

```
flappy pipe --to 127.0.0.1:3000 --listen 8080 --level the_tunnel
flappy pipe --to staging.example.com:80 --up-kbps 48 --latency 400
```

## Change the weather from outside Ruby

Most real tests sign in on a good connection and only then hit bad weather. Give
the pipe a control panel and any test, in any language, can flip the weather
while it runs:

```
flappy pipe --to 127.0.0.1:3000 --listen 8080 --control 8081
```

```
curl -X POST localhost:8081/level/the_tunnel?speed=3   # start a level
curl -X POST localhost:8081/offline                    # cut everything
curl -X POST localhost:8081/conditions -d '{"latency": 300, "up_kbps": 64}'
curl -X POST localhost:8081/clear                      # clear skies
curl localhost:8081/                                   # what is it doing now?
```

In a Playwright test:

```js
await signIn(page)                                            // clear skies
await fetch('http://127.0.0.1:8081/level/the_tunnel', { method: 'POST' })
// ...now exercise the offline behaviour...
await fetch('http://127.0.0.1:8081/clear', { method: 'POST' })
```

From Ruby, pass `control: 0` to `Flappy.pipe` and read `pipe.control_url`, or just
set `pipe.conditions` directly. The control panel listens on localhost only. Do
not expose it.

## How it works

A pipe is a small TCP proxy. It listens on a port, connects to your server, and
passes bytes both ways, with the current conditions applied on the way through.
Because it only moves bytes, HTTPS works untouched. Nothing is decrypted and
there are no certificates to trust.

## Limits

Flappy Rails flaps the network between your client and your server. It does not
fake what a phone or browser does when the signal goes. If you need the real
device behaviour, such as an app being suspended in a pocket, test on a device.
Use Flappy Rails for everything that happens before that point, which is a lot.

## Development

```
bundle install
bundle exec rake test
```

## Credits

Built by [Jay Killeen](https://github.com/jaykilleen) and
[Vanessa Soares](https://github.com/rsvanessasoaresss) at
[Retail Tasker](https://www.retailtasker.com.au), from testing an app for
people who work in stores with patchy signal.

## Licence

MIT. See [LICENSE](LICENSE).
