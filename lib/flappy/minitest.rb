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
    def flappy_pipe(to:, level: Flappy.configured_level, speed: Flappy.configured_speed, seed: Flappy.configured_seed, **options)
      pipe = Flappy.pipe(to: to, seed: seed, **options)
      player = level ? Flappy.level(level).play(pipe, speed: speed) : nil
      (@flappy_running ||= []) << [pipe, player]
      pipe
    end

    # Rails system tests: put the pipe between the browser and the Capybara
    # server. Call it from setup, before the first visit.
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
      ::Capybara.app_host = @flappy_previous_app_host if @flappy_capybara
      super
    end
  end
end
