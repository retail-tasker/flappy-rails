require "test_helper"
require "flappy/minitest"
require "net/http"

class MinitestHelperTest < Minitest::Test
  include Flappy::Minitest
  include PipeHelpers

  def teardown
    ENV.delete("FLAPPY_LEVEL")
    super
  end

  def test_pipe_is_clear_skies_when_no_level_is_configured
    ENV.delete("FLAPPY_LEVEL")
    start_echo
    pipe = flappy_pipe(to: @echo.address)

    assert_predicate pipe.conditions, :clear?
  end

  def test_pipe_plays_the_level_flappy_run_asked_for
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address)

    assert_equal Flappy.level(:the_tunnel).phases.first.conditions, pipe.conditions
  end

  def test_calm_pipe_stays_clear_until_the_weather_is_started
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)

    assert_predicate pipe.conditions, :clear?
    assert_nil pipe.playing

    flappy_weather!

    assert_equal Flappy.level(:the_tunnel), pipe.playing
    assert_equal Flappy.level(:the_tunnel).phases.first.conditions, pipe.conditions
  end

  def test_weather_does_nothing_without_a_level
    ENV.delete("FLAPPY_LEVEL")
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)

    assert_nil flappy_weather!
    assert_predicate pipe.conditions, :clear?
  end

  def test_weather_starts_once
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)
    flappy_weather!
    player = pipe.instance_variable_get(:@player)
    flappy_weather!

    assert_same player, pipe.instance_variable_get(:@player)
  end

  def test_pipes_are_stopped_after_the_test
    start_echo
    pipe = flappy_pipe(to: @echo.address)
    port = pipe.port
    after_teardown

    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new("127.0.0.1", port) }
  end

  def test_http_through_a_pipe
    server = TCPServer.new("127.0.0.1", 0)
    Thread.new do
      Thread.current.report_on_exception = false
      client = server.accept
      client.readpartial(4096)
      client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nup")
      client.close
    end
    pipe = flappy_pipe(to: "127.0.0.1:#{server.addr[1]}")

    assert_equal "up", Net::HTTP.get(URI("#{pipe.url}/up"))
  ensure
    server&.close
  end
end
