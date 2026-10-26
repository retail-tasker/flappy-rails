module Flappy
  # The pipe maze. Each level is meaner than the one before it.
  module Levels
    ALL = [
      Level.new(
        name: :warm_up,
        title: "Warm-Up Wobble",
        tagline: "A little shaky, nothing a retry won't fix.",
        phases: [Level.phase(10, "wobbling", latency: 150, jitter: 100)]
      ),
      Level.new(
        name: :potholes,
        title: "Pothole Pass",
        tagline: "Slow roads, and every so often the connection just dies.",
        phases: [Level.phase(10, "potholes", latency: 300, jitter: 300, reset_chance: 0.05)]
      ),
      Level.new(
        name: :the_tunnel,
        title: "The Tunnel",
        tagline: "20 seconds of signal, 5 seconds of nothing, on repeat.",
        phases: [Level.phase(20, "signal"), Level.phase(5, "tunnel", offline: true)]
      ),
      Level.new(
        name: :dead_zone,
        title: "Dead Zone",
        tagline: "Connected on paper. Nothing moves for 15 seconds at a time.",
        phases: [Level.phase(10, "signal"), Level.phase(15, "dead zone", stall: true)]
      ),
      Level.new(
        name: :rural_run,
        title: "Rural Run",
        tagline: "One bar, slow uploads, and the odd dropped connection.",
        phases: [Level.phase(15, "one bar", latency: 400, jitter: 400, up_kbps: 48, down_kbps: 256, reset_chance: 0.03)]
      ),
      Level.new(
        name: :the_lift,
        title: "The Lift (boss)",
        tagline: "Signal, no signal, stuck, crawling. Every few seconds.",
        phases: [
          Level.phase(3, "signal"),
          Level.phase(2, "doors close", offline: true),
          Level.phase(3, "stuck between floors", stall: true),
          Level.phase(4, "one bar", latency: 500, jitter: 500, up_kbps: 32, down_kbps: 128)
        ]
      )
    ].freeze

    def self.find(key)
      case key
      when Level then key
      when Integer then ALL[key - 1] || raise(Flappy::Error, "no level #{key}, there are #{ALL.size}")
      else
        text = key.to_s
        return ALL[text.to_i - 1] || raise(Flappy::Error, "no level #{text}, there are #{ALL.size}") if text.match?(/\A\d+\z/)

        ALL.find { |l| l.name.to_s == text.tr("-", "_") } || raise(Flappy::Error, "no level called #{key.inspect}, try one of: #{ALL.map(&:name).join(', ')}")
      end
    end
  end
end
