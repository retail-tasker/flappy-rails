$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "socket"
require "flappy"

# A tiny TCP echo server to point pipes at.
class EchoServer
  attr_reader :port

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new do
      Thread.current.report_on_exception = false
      loop do
        client = @server.accept
        Thread.new(client) do |c|
          Thread.current.report_on_exception = false
          loop { c.write(c.readpartial(4096)) }
        rescue EOFError, IOError, SystemCallError
          c.close unless c.closed?
        end
      end
    rescue IOError, SystemCallError
      nil
    end
  end

  def address
    "127.0.0.1:#{@port}"
  end

  def stop
    @server.close
    @thread.join(1)
  end
end

module PipeHelpers
  def start_echo
    @echo = EchoServer.new
  end

  def start_pipe(**options)
    start_echo unless @echo
    @pipe = Flappy.pipe(to: @echo.address, **options)
  end

  def teardown
    @pipe&.stop
    @echo&.stop
    super
  end

  def elapsed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  # Send a message through the pipe and read the same number of bytes back.
  def round_trip(message, timeout: 5)
    socket = TCPSocket.new("127.0.0.1", @pipe.port)
    socket.write(message)
    received = +""
    while received.bytesize < message.bytesize
      raise "timed out after #{received.bytesize} of #{message.bytesize} bytes" unless IO.select([socket], nil, nil, timeout)

      received << socket.readpartial(65_536)
    end
    received
  ensure
    socket&.close
  end
end
