require "test_helper"

class LevelTest < Minitest::Test
  include PipeHelpers

  def level
    Flappy::Level.new(
      name: :test_loop,
      title: "Test Loop",
      tagline: "up, down, repeat",
      phases: [Flappy::Level.phase(0.2, "up"), Flappy::Level.phase(0.2, "down", offline: true)]
    )
  end

  def test_a_level_loops_through_its_phases
    start_pipe
    player = level.play(@pipe)
    seen = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.2
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      seen << @pipe.conditions.offline
      sleep 0.02
    end
    player.stop

    assert_includes seen, true
    assert_includes seen, false
    transitions = seen.each_cons(2).count { |a, b| a != b }
    assert_operator transitions, :>=, 3, "a 0.4s cycle seen for 1.2s should flip at least 3 times"
  end

  def test_speed_plays_the_weather_faster
    start_pipe
    player = level.play(@pipe, speed: 10)
    flips = 0
    last = @pipe.conditions.offline
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.6
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      now = @pipe.conditions.offline
      flips += 1 if now != last
      last = now
      sleep 0.005
    end
    player.stop
    assert_operator flips, :>=, 6
  end

  def test_stopping_leaves_clear_skies
    start_pipe
    player = level.play(@pipe)
    sleep 0.3
    player.stop
    assert_predicate @pipe.conditions, :clear?
  end

  def test_built_in_levels_are_findable_by_number_and_name
    assert_equal :warm_up, Flappy.level(1).name
    assert_equal :the_tunnel, Flappy.level("the-tunnel").name
    assert_equal :the_lift, Flappy.level(:the_lift).name
    assert_equal 6, Flappy.levels.size
    assert_raises(Flappy::Error) { Flappy.level("nope") }
    assert_raises(Flappy::Error) { Flappy.level(99) }
  end

  def test_every_built_in_level_has_at_least_one_phase_with_time_on_the_clock
    Flappy.levels.each do |l|
      assert_operator l.cycle_seconds, :>, 0, l.title
    end
  end
end
