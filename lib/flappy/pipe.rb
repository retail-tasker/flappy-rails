require "socket"

module Flappy
  # A TCP proxy with a dial on it. Point your client at the pipe instead of the
  # server and the pipe passes every byte along, with whatever the current
  # Conditions say should happen to it on the way.
  #
  # It only moves bytes, so HTTPS passes through untouched: nothing is decrypted
  # and no certificates need trusting.
  #
  #   pipe = Flappy::Pipe.new(to: "127.0.0.1:3000").start
  #   pipe.conditions = Flappy::Conditions.new(latency: 300, up_kbps: 64)
  #   Net::HTTP.get(URI("#{pipe.url}/up"))
  #   pipe.stop
  class Pipe
    CHUNK = 16_384
    SLOW_CHUNK = 1_024
    IDLE_GAP = 0.05 # seconds of quiet before the next burst pays latency again

    attr_reader :host, :port, :to_host, :to_port

    # control: pass a port (0 for any free one) to also start a small HTTP
    # control server, so tests in any language can change the weather mid-run.
    def initialize(to:, port: 0, host: "127.0.0.1", conditions: Conditions.new, seed: nil, on_event: nil, control: nil)
      @to_host, @to_port = parse_target(to)
      @host = host
      @listen_port = port
      @control_port = control
      @conditions = conditions
      @random = Random.new(seed || Random.new_seed)
      @mutex = Mutex.new
      @connections = []
      @stats = Hash.new(0)
      @on_event = on_event
      @running = false
    end

    def start
      return self if @running

      @server = TCPServer.new(@host, @listen_port)
      @port = @server.addr[1]
      @running = true
      @acceptor = Thread.new { accept_loop }
      @acceptor.report_on_exception = false
      @control = Control.new(self, port: @control_port, host: @host).start unless @control_port.nil?
      self
    end

    # Play a level on this pipe, replacing any level already playing.
    def play(level, speed: 1.0)
      stop_level
      @player = Flappy.level(level).play(self, speed: speed)
    end

    def stop_level
      @player&.stop
      @player = nil
    end

    def playing
      @player&.level
    end

    def control_url
      @control&.url
    end

    def stop
      @running = false
      stop_level
      @control&.stop
      begin
        @server&.close
      rescue IOError, SystemCallError
        nil
      end
      reset_all
      @acceptor&.join(2)
      self
    end

    def url(scheme = "http")
      "#{scheme}://#{@host}:#{@port}"
    end

    def conditions
      @conditions
    end

    def conditions=(new_conditions)
      old = nil
      @mutex.synchronize do
        old = @conditions
        @conditions = new_conditions
      end
      emit(:conditions, new_conditions)
      reset_all if new_conditions.offline && !old.offline
    end

    # Run a block under temporary conditions, then put the old ones back.
    def under(conditions)
      previous = self.conditions
      self.conditions = conditions
      yield self
    ensure
      self.conditions = previous
    end

    def clear!
      self.conditions = Conditions.new
    end

    def offline!
      self.conditions = Conditions.new(offline: true)
    end

    def stall!
      self.conditions = Conditions.new(stall: true)
    end

    def stats
      @mutex.synchronize { @stats.dup }
    end

    private

    Connection = Struct.new(:client, :upstream)

    def parse_target(to)
      host, port = to.to_s.split(":", 2)
      raise Flappy::Error, "pipe target must look like host:port, got #{to.inspect}" if host.to_s.empty? || port.to_s.empty?

      [host, Integer(port)]
    end

    def accept_loop
      while @running
        client = @server.accept
        handle(client)
      end
    rescue IOError, SystemCallError
      nil
    end

    def handle(client)
      if conditions.offline
        count(:refused)
        emit(:refused)
        hard_close(client)
        return
      end

      Thread.new do
        Thread.current.report_on_exception = false
        serve(client)
      end
    end

    def serve(client)
      wait_while_stalled
      upstream = TCPSocket.new(@to_host, @to_port)
      [client, upstream].each { |s| s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) }
      connection = Connection.new(client, upstream)
      @mutex.synchronize { @connections << connection }
      count(:connections)
      doom(connection) if rolled_doomed?

      up = Thread.new { pump(client, upstream, :up, connection) }
      down = Thread.new { pump(upstream, client, :down, connection) }
      [up, down].each do |t|
        t.report_on_exception = false
        t.join
      end
    rescue IOError, SystemCallError
      nil
    ensure
      @mutex.synchronize { @connections.delete(connection) } if connection
      [client, upstream].compact.each do |s|
        s.close
      rescue IOError, SystemCallError
        nil
      end
    end

    def pump(source, destination, direction, connection)
      last_sent = nil
      loop do
        kbps = kbps_for(conditions, direction)
        data = source.readpartial(kbps ? SLOW_CHUNK : CHUNK)
        wait_while_stalled
        current = conditions
        raise IOError, "offline" if current.offline

        now = monotonic
        pause(current) if last_sent.nil? || now - last_sent > IDLE_GAP
        destination.write(data)
        count(direction == :up ? :bytes_up : :bytes_down, data.bytesize)
        kbps = kbps_for(current, direction)
        sleep(data.bytesize * 8.0 / (kbps * 1000.0)) if kbps
        last_sent = monotonic
      end
    rescue EOFError
      begin
        destination.close_write
      rescue IOError, SystemCallError
        nil
      end
    rescue IOError, SystemCallError
      nil
    end

    # reset_chance is rolled once per connection, not per chunk, so a big page
    # load is not cut just for being big. A doomed connection works for a
    # moment and then dies, the way a dropped signal does.
    def rolled_doomed?
      chance = conditions.reset_chance
      chance.positive? && @random.rand < chance
    end

    def doom(connection)
      delay = 0.05 + (@random.rand * 1.5)
      Thread.new do
        Thread.current.report_on_exception = false
        sleep(delay)
        next unless @mutex.synchronize { @connections.include?(connection) }

        count(:resets)
        emit(:reset)
        reset(connection)
      end
    end

    def kbps_for(conditions, direction)
      direction == :up ? conditions.up_kbps : conditions.down_kbps
    end

    def pause(conditions)
      ms = conditions.latency + (conditions.jitter.positive? ? @random.rand * conditions.jitter : 0)
      sleep(ms / 1000.0) if ms.positive?
    end

    def wait_while_stalled
      sleep(0.02) while @running && conditions.stall && !conditions.offline
    end

    def reset_all
      @mutex.synchronize { @connections.dup }.each { |c| reset(c) }
    end

    def reset(connection)
      hard_close(connection.client)
      hard_close(connection.upstream)
    end

    # Close with SO_LINGER 0 so the peer sees a reset, like a dropped signal.
    def hard_close(socket)
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
      socket.close
    rescue IOError, SystemCallError
      nil
    end

    def count(key, amount = 1)
      @mutex.synchronize { @stats[key] += amount }
    end

    def emit(event, *args)
      @on_event&.call(event, *args)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
