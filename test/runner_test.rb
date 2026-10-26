require "test_helper"
require "stringio"
require "tmpdir"
require "rbconfig"

class RunnerTest < Minitest::Test
  # Passes on the first level only, so level 1 clears and the rest crash.
  PASS_ON_WARM_UP = [RbConfig.ruby, "-e", "exit(ENV['FLAPPY_LEVEL'] == 'warm_up' ? 0 : 1)"].freeze

  def run_gauntlet(command, **options)
    out = StringIO.new
    Dir.mktmpdir do |dir|
      runner = Flappy::Runner.new(command: command, levels: [1, 2, 3], times: 2, seed: 1, log_dir: dir, out: out, **options)
      success = runner.run
      return [runner, success, out.string, Dir.children(dir)]
    end
  end

  def test_scores_levels_cleared_in_a_row
    runner, success, output, logs = run_gauntlet(PASS_ON_WARM_UP)

    refute success
    assert_equal 1, runner.score
    assert_equal [2, 0, 0], runner.results.map(&:survived)
    assert_match(/LEVEL 1: Warm-Up Wobble/, output)
    assert_match(/Final score: 1 of 3 levels cleared/, output)
    assert_equal 4, logs.size, "levels 2 and 3 crashed twice each"
  end

  def test_sudden_death_stops_at_the_first_crash
    runner, _success, output, _logs = run_gauntlet(PASS_ON_WARM_UP, sudden_death: true)

    assert_equal 2, runner.results.size
    assert_match(/1 level not played/, output)
  end

  def test_a_clean_sweep_clears_every_level
    runner, success, output, = run_gauntlet([RbConfig.ruby, "-e", "exit 0"])

    assert success
    assert_equal 3, runner.score
    assert_match(/Every pipe, no crashes/, output)
  end

  def test_children_see_the_level_in_their_environment
    command = [RbConfig.ruby, "-e", "exit(ENV.values_at('FLAPPY_LEVEL', 'FLAPPY_SPEED', 'FLAPPY_SEED', 'FLAPPY_RUN').all? ? 0 : 1)"]
    _runner, success, = run_gauntlet(command)

    assert success
  end

  def test_pass_rate_allows_the_odd_crash
    flaky = [RbConfig.ruby, "-e", "exit(ENV['FLAPPY_RUN'] == '1' ? 1 : 0)"]
    runner, success, = run_gauntlet(flaky, pass_rate: 0.5)

    assert success
    assert_equal [1, 1, 1], runner.results.map(&:survived)
  end

  def test_a_command_that_cannot_start_counts_as_a_crash
    runner, success, = run_gauntlet(["definitely-not-a-real-command-flappy"])

    refute success
    assert_equal 0, runner.score
  end
end
