require_relative "flappy/version"
require_relative "flappy/conditions"
require_relative "flappy/control"
require_relative "flappy/pipe"
require_relative "flappy/level"
require_relative "flappy/levels"
require_relative "flappy/runner"

# Flappy Rails: a flaky network for your test suite. Can your signal make it
# through the pipes?
module Flappy
  class Error < StandardError; end

  class << self
    # Build and start a pipe in front of host:port.
    #
    #   pipe = Flappy.pipe(to: "127.0.0.1:3000")
    def pipe(to:, **options)
      Pipe.new(to: to, **options).start
    end

    def levels
      Levels::ALL
    end

    # Look a level up by number (1), name (:the_tunnel or "the-tunnel") or pass a Level through.
    def level(key)
      Levels.find(key)
    end

    # The level the `flappy run` gauntlet asked for, or nil when you are
    # running your tests normally. Set through FLAPPY_LEVEL.
    def configured_level
      name = ENV["FLAPPY_LEVEL"].to_s.strip
      name.empty? ? nil : Levels.find(name)
    end

    def configured_speed
      Float(ENV.fetch("FLAPPY_SPEED", "1.0"))
    rescue ArgumentError
      1.0
    end

    def configured_seed
      ENV["FLAPPY_SEED"]&.then { |s| Integer(s, exception: false) }
    end
  end
end
