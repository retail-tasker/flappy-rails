module Flappy
  # A level is a short loop of weather. Each phase sets the pipe's conditions
  # for a number of seconds, then the next phase takes over, and the whole
  # thing repeats until the level is stopped.
  class Level
    Phase = Data.define(:seconds, :conditions, :label)

    attr_reader :name, :title, :tagline, :phases

    def self.phase(seconds, label = nil, **conditions)
      Phase.new(seconds: seconds.to_f, conditions: Conditions.new(**conditions), label: label || Conditions.new(**conditions).describe)
    end

    def initialize(name:, title:, tagline:, phases:)
      @name = name.to_sym
      @title = title
      @tagline = tagline
      @phases = phases.freeze
      raise Flappy::Error, "level #{name} needs at least one phase" if @phases.empty?
    end

    # Start playing this level on a pipe. Returns a Player; call stop when done.
    # speed 2.0 plays everything twice as fast, which is handy for short suites.
    def play(pipe, speed: 1.0)
      Player.new(pipe, self, speed).start
    end

    def cycle_seconds
      phases.sum(&:seconds)
    end

    class Player
      attr_reader :level

      def initialize(pipe, level, speed)
        @pipe = pipe
        @level = level
        @speed = speed.to_f.positive? ? speed.to_f : 1.0
        @stopped = false
      end

      def start
        @thread = Thread.new do
          Thread.current.report_on_exception = false
          until @stopped
            @level.phases.each do |phase|
              break if @stopped

              @pipe.conditions = phase.conditions
              wait(phase.seconds / @speed)
            end
          end
        end
        self
      end

      def stop
        @stopped = true
        @thread&.join(2)
        @pipe.clear!
        self
      end

      private

      def wait(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        sleep(0.02) while !@stopped && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      end
    end
  end
end
