require "socket"
require "json"
require "uri"

module Flappy
  # A tiny HTTP control panel for a pipe, so a test in any language can change
  # the weather while it runs. Sign in on clear skies, then start the storm.
  #
  #   GET  /                 current conditions, level and stats
  #   POST /clear            clear skies (also stops any level)
  #   POST /offline          cut everything and refuse new connections
  #   POST /stall            hold all traffic
  #   POST /level/the_tunnel start a level (add ?speed=3 to play it faster)
  #   POST /conditions       JSON body, e.g. {"latency": 300, "up_kbps": 64}
  #
  # It listens on localhost only. Do not expose it.
  class Control
    attr_reader :port

    def initialize(pipe, port: 0, host: "127.0.0.1")
      @pipe = pipe
      @host = host
      @listen_port = port
      @running = false
    end

    def start
      @server = TCPServer.new(@host, @listen_port)
      @port = @server.addr[1]
      @running = true
      @thread = Thread.new { accept_loop }
      @thread.report_on_exception = false
      self
    end

    def stop
      @running = false
      begin
        @server&.close
      rescue IOError, SystemCallError
        nil
      end
      @thread&.join(1)
      self
    end

    def url
      "http://#{@host}:#{@port}"
    end

    private

    def accept_loop
      while @running
        client = @server.accept
        Thread.new(client) do |socket|
          Thread.current.report_on_exception = false
          handle(socket)
        end
      end
    rescue IOError, SystemCallError
      nil
    end

    def handle(socket)
      request_line = socket.gets.to_s.strip
      method, target, = request_line.split(" ", 3)
      length = 0
      while (line = socket.gets) && line.strip != ""
        length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
      end
      body = length.positive? ? socket.read(length).to_s : ""

      status, payload = route(method, URI.parse(target.to_s), body)
      respond(socket, status, payload)
    rescue URI::InvalidURIError, JSON::ParserError => e
      respond(socket, 400, error: e.message)
    rescue Flappy::Error, ArgumentError => e
      respond(socket, 422, error: e.message)
    rescue IOError, SystemCallError
      nil
    ensure
      begin
        socket.close
      rescue IOError, SystemCallError
        nil
      end
    end

    def route(method, uri, body)
      return [204, nil] if method == "OPTIONS"

      path = uri.path
      query = URI.decode_www_form(uri.query.to_s).to_h
      case [method, path]
      in ["GET", "/" | "/state"] then [200, state]
      in ["POST", "/clear"] then apply { @pipe.stop_level; @pipe.clear! }
      in ["POST", "/offline"] then apply { @pipe.stop_level; @pipe.offline! }
      in ["POST", "/stall"] then apply { @pipe.stop_level; @pipe.stall! }
      in ["POST", "/conditions"] then apply { set_conditions(JSON.parse(body.empty? ? "{}" : body)) }
      in ["POST", %r{\A/level/(?<name>[\w-]+)\z}] then apply { @pipe.play(Regexp.last_match[:name], speed: Float(query.fetch("speed", "1"))) }
      else [404, { error: "no such route", routes: ["GET /", "POST /clear", "POST /offline", "POST /stall", "POST /level/NAME", "POST /conditions"] }]
      end
    end

    def apply
      yield
      [200, state]
    end

    def set_conditions(options)
      @pipe.stop_level
      @pipe.conditions = Conditions.new(**options.transform_keys(&:to_sym))
    end

    def state
      conditions = @pipe.conditions
      {
        conditions: conditions.to_h,
        describe: conditions.describe,
        level: @pipe.playing&.name,
        stats: @pipe.stats
      }
    end

    def respond(socket, status, payload)
      body = payload.nil? ? "" : JSON.generate(payload)
      reasons = { 200 => "OK", 204 => "No Content", 400 => "Bad Request", 404 => "Not Found", 422 => "Unprocessable Entity" }
      socket.write("HTTP/1.1 #{status} #{reasons.fetch(status, 'OK')}\r\n" \
                   "Content-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\n" \
                   "Access-Control-Allow-Headers: content-type\r\nConnection: close\r\n\r\n#{body}")
    end
  end
end
