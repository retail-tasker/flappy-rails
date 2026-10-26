module Flappy
  # What the network is doing to your traffic right now. A Conditions value is
  # immutable: swap a whole new one into a pipe to change the weather.
  #
  #   latency       milliseconds added each time traffic starts moving
  #   jitter        up to this many extra milliseconds, picked at random
  #   up_kbps       cap on client to server speed (nil means no cap)
  #   down_kbps     cap on server to client speed (nil means no cap)
  #   reset_chance  0.0 to 1.0, chance that a new connection is cut dead a moment after it opens
  #   stall         true holds all traffic (and new connections) until it clears
  #   offline       true refuses new connections and cuts the ones in flight
  Conditions = Data.define(:latency, :jitter, :up_kbps, :down_kbps, :reset_chance, :stall, :offline) do
    def initialize(latency: 0, jitter: 0, up_kbps: nil, down_kbps: nil, reset_chance: 0.0, stall: false, offline: false)
      super
    end

    def clear?
      self == Conditions.new
    end

    def describe
      return "clear skies" if clear?
      return "offline" if offline
      return "stalled" if stall

      parts = []
      parts << "latency #{latency}ms" + (jitter.positive? ? " +/- #{jitter}" : "") if latency.positive? || jitter.positive?
      parts << "up #{up_kbps}kbps" if up_kbps
      parts << "down #{down_kbps}kbps" if down_kbps
      parts << "resets #{(reset_chance * 100).round(1)}% of connections" if reset_chance.positive?
      parts.join(", ")
    end
  end
end
