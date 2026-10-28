require "flappy"

module Flappy
  # Drop-in helper for Minitest (and Rails tests built on it).
  #
  #   class CheckoutTest < ActiveSupport::TestCase
  #     include Flappy::Minitest
  #
  #     test "survives a flaky connection" do
  #       pipe = flappy_pipe(to: "127.0.0.1:3000")
  #       Net::HTTP.get(URI("#{pipe.url}/up"))
  #     end
  #   end
  #
  # When a test is run by `flappy run`, FLAPPY_LEVEL picks the level and the pipe
  # plays it for the length of the test. Run the suite normally and the pipe
  # is clear skies, so the same tests work either way.
  module Minitest
    # Start a pipe in front of `to`, playing the configured level. It is stopped
    # for you when the test finishes.
    #
    # Pass `calm: true` to keep the pipe on clear skies until you call
    # `flappy_weather!`. Setup (signing in, installing a service worker, seeding
    # data) usually is not the thing under test, and bad weather there fails
    # the test before it starts.
    def flappy_pipe(to:, level: Flappy.configured_level, speed: Flappy.configured_speed, seed: Flappy.configured_seed, calm: false, **options)
      pipe = Flappy.pipe(to: to, seed: seed, **options)
      player = level && !calm ? Flappy.level(level).play(pipe, speed: speed) : nil
      (@flappy_running ||= []) << [pipe, player]
      (@flappy_calm ||= []) << [pipe, level, speed] if calm && level
      pipe
    end

    # Start the weather on every pipe that was created with `calm: true`. Does
    # nothing when there is no level to play, so the same test runs unchanged
    # outside `flappy run`.
    def flappy_weather!
      (@flappy_calm || []).each { |pipe, level, speed| pipe.play(level, speed: speed) }
      @flappy_calm = []
      nil
    end

    # Rails system tests: put the pipe between the browser and the Capybara
    # server. Call it from setup, before the first visit. Takes the same options
    # as `flappy_pipe`, including `calm: true`.
    def flappy_capybara(level: Flappy.configured_level, **options)
      raise Flappy::Error, "Capybara is not loaded" unless defined?(::Capybara)

      server = ::Capybara.current_session.server
      raise Flappy::Error, "Capybara has no server to put a pipe in front of" unless server

      server.boot
      @flappy_previous_app_host = ::Capybara.app_host
      @flappy_capybara = true
      pipe = flappy_pipe(to: "#{server.host}:#{server.port}", level: level, **options)
      ::Capybara.app_host = pipe.url
      pipe
    end

    def after_teardown
      (@flappy_running || []).each do |pipe, player|
        player&.stop
        pipe.stop
      end
      @flappy_running = []
      @flappy_calm = []
      ::Capybara.app_host = @flappy_previous_app_host if @flappy_capybara
      super
    end
  end
end
