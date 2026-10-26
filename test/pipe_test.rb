require "test_helper"

class PipeTest < Minitest::Test
  include PipeHelpers

  def test_clear_skies_passes_bytes_straight_through
    start_pipe
    assert_equal "hello pipe", round_trip("hello pipe")
    assert_equal 1, @pipe.stats[:connections]
  end

  def test_counts_bytes_in_both_directions
    start_pipe
    round_trip("x" * 500)
    assert_equal 500, @pipe.stats[:bytes_up]
    assert_equal 500, @pipe.stats[:bytes_down]
  end

  def test_latency_slows_each_flight
    start_pipe(conditions: Flappy::Conditions.new(latency: 150))
    seconds = elapsed { round_trip("ping") }
    assert_operator seconds, :>=, 0.25, "one flight each way should cost at least 2 x 150ms"
  end

  def test_upload_speed_cap_throttles_uploads
    start_pipe(conditions: Flappy::Conditions.new(up_kbps: 128))
    seconds = elapsed { round_trip("a" * 8_000) } # 64 kilobits at 128 kbps is half a second
    assert_operator seconds, :>=, 0.35
  end

  def test_reset_chance_cuts_the_connection
    start_pipe(conditions: Flappy::Conditions.new(reset_chance: 1.0))
    socket = TCPSocket.new("127.0.0.1", @pipe.port)
    socket.write("doomed")
    assert_raises(EOFError, Errno::ECONNRESET) do
      IO.select([socket], nil, nil, 2)
      socket.readpartial(100)
    end
    assert_operator @pipe.stats[:resets], :>=, 1
  ensure
    socket&.close
  end

  def test_offline_refuses_new_connections
    start_pipe
    @pipe.offline!
    socket = TCPSocket.new("127.0.0.1", @pipe.port)
    assert_raises(EOFError, Errno::ECONNRESET) do
      IO.select([socket], nil, nil, 2)
      socket.readpartial(100)
    end
    assert_equal 1, @pipe.stats[:refused]
  ensure
    socket&.close
  end

  def test_going_offline_cuts_connections_already_open
    start_pipe
    socket = TCPSocket.new("127.0.0.1", @pipe.port)
    socket.write("hi")
    IO.select([socket], nil, nil, 2)
    assert_equal "hi", socket.readpartial(10)

    @pipe.offline!
    assert_raises(EOFError, Errno::ECONNRESET) do
      IO.select([socket], nil, nil, 2)
      socket.readpartial(10)
    end
  ensure
    socket&.close
  end

  def test_stall_holds_traffic_then_lets_it_go
    start_pipe
    socket = TCPSocket.new("127.0.0.1", @pipe.port)
    @pipe.stall!
    socket.write("stuck")
    assert_nil IO.select([socket], nil, nil, 0.4), "nothing should arrive while stalled"

    @pipe.clear!
    assert IO.select([socket], nil, nil, 2), "traffic should resume once the stall clears"
    assert_equal "stuck", socket.readpartial(10)
  ensure
    socket&.close
  end

  def test_under_restores_the_previous_conditions
    start_pipe
    @pipe.under(Flappy::Conditions.new(latency: 10)) do |pipe|
      assert_equal 10, pipe.conditions.latency
    end
    assert_predicate @pipe.conditions, :clear?
  end

  def test_target_must_look_like_host_and_port
    assert_raises(Flappy::Error) { Flappy::Pipe.new(to: "nonsense") }
  end

  def test_describe_reads_like_the_weather
    assert_equal "clear skies", Flappy::Conditions.new.describe
    assert_equal "offline", Flappy::Conditions.new(offline: true).describe
    assert_match(/latency 300ms \+\/- 100, up 64kbps/, Flappy::Conditions.new(latency: 300, jitter: 100, up_kbps: 64).describe)
  end
end
