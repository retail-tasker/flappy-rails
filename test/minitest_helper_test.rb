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

    assert_equal [], flappy_weather!
    assert_predicate pipe.conditions, :clear?
  end

  def test_weather_returns_the_pipes_it_started
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)

    assert_equal [pipe], flappy_weather!
    assert_equal [], flappy_weather!
  end

  def test_weather_can_start_one_pipe_of_two
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    app = flappy_pipe(to: @echo.address, calm: true)
    api = flappy_pipe(to: @echo.address, calm: true)

    assert_equal [app], flappy_weather!(app)
    assert_equal Flappy.level(:the_tunnel), app.playing
    assert_nil api.playing

    assert_equal [api], flappy_weather!
    assert_equal Flappy.level(:the_tunnel), api.playing
    flappy_weather!
  end

  def test_weather_does_nothing_when_nothing_is_calm
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    flappy_pipe(to: @echo.address)

    assert_equal [], flappy_weather!
  end

  def test_late_started_weather_is_stopped_after_the_test
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)
    flappy_weather!
    port = pipe.port
    after_teardown

    assert_nil pipe.playing
    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new("127.0.0.1", port) }
  end

  def test_a_calm_pipe_that_never_gets_weather_fails_the_test
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    pipe = flappy_pipe(to: @echo.address, calm: true)
    port = pipe.port

    error = assert_raises(Flappy::Error) { after_teardown }
    assert_match(/flappy_weather!/, error.message)
    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new("127.0.0.1", port) }
  end

  def test_calm_is_passed_through_flappy_capybara
    ENV["FLAPPY_LEVEL"] = "the_tunnel"
    start_echo
    host, port = @echo.address.split(":")
    server = Struct.new(:host, :port) { def boot = self }.new(host, port.to_i)
    session = Struct.new(:server).new(server)
    capybara = Module.new do
      class << self
        attr_accessor :app_host, :session
        def current_session = session
      end
    end
    capybara.session = session
    Object.const_set(:Capybara, capybara)
    pipe = flappy_capybara(calm: true)

    assert_predicate pipe.conditions, :clear?
    assert_equal pipe.url, Capybara.app_host
    flappy_weather!
    assert_equal Flappy.level(:the_tunnel), pipe.playing
  ensure
    # The framework runs after_teardown again once this test ends, and it
    # touches Capybara only when flappy_capybara was used.
    after_teardown
    @flappy_capybara = nil
    Object.send(:remove_const, :Capybara) if defined?(::Capybara)
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
