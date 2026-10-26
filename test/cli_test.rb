require "test_helper"
require "flappy/cli"
require "stringio"

class CLITest < Minitest::Test
  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Flappy::CLI.start(argv, out: out, err: err)
    [status, out.string, err.string]
  end

  def test_version
    status, out, = run_cli("version")
    assert_equal 0, status
    assert_equal "#{Flappy::VERSION}\n", out
  end

  def test_levels_lists_every_level
    status, out, = run_cli("levels")
    assert_equal 0, status
    Flappy.levels.each { |l| assert_includes out, l.title }
  end

  def test_run_without_a_command_explains_itself
    status, _out, err = run_cli("run", "--times", "1")
    assert_equal 2, status
    assert_match(/give flappy a command/, err)
  end

  def test_pipe_needs_a_target
    status, _out, err = run_cli("pipe")
    assert_equal 2, status
    assert_match(/--to HOST:PORT is required/, err)
  end

  def test_unknown_command
    status, _out, err = run_cli("fly")
    assert_equal 2, status
    assert_match(/unknown command/, err)
  end

  def test_run_plays_the_gauntlet_and_reports_the_exit_status
    status, out, = run_cli("run", "--levels", "1,2", "--times", "1", "--log-dir", Dir.tmpdir, "--", RbConfig.ruby, "-e", "exit 0")
    assert_equal 0, status
    assert_match(/Final score: 2 of 2 levels cleared/, out)
  end
end
