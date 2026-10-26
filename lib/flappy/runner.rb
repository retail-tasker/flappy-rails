require "open3"
require "fileutils"

module Flappy
  # The gauntlet. Runs a command (your test suite) over and over, level by
  # level, with FLAPPY_LEVEL set so Flappy::Minitest puts a flaky pipe in front
  # of your app. A level is cleared when enough runs survive.
  class Runner
    Result = Struct.new(:level, :runs, :survived, :failed_logs, keyword_init: true) do
      def cleared?(pass_rate)
        runs.positive? && survived.to_f / runs >= pass_rate
      end
    end

    attr_reader :results

    def initialize(command:, levels: Levels::ALL, times: 10, speed: 1.0, seed: nil, sudden_death: false,
                   pass_rate: 1.0, log_dir: "tmp/flappy", out: $stdout, verbose: false)
      @command = command
      @levels = levels.map { |l| Levels.find(l) }
      @times = times
      @speed = speed
      @seed = seed || Random.new_seed % 100_000
      @sudden_death = sudden_death
      @pass_rate = pass_rate
      @log_dir = log_dir
      @out = out
      @verbose = verbose
      @results = []
    end

    # Returns true when every level that was played got cleared.
    def run
      banner
      @levels.each_with_index do |level, index|
        result = play(level, index + 1)
        @results << result
        break if @sudden_death && !result.cleared?(@pass_rate)
      end
      scoreboard
      @results.size == @levels.size && @results.all? { |r| r.cleared?(@pass_rate) }
    end

    # Levels cleared in a row from level 1, like pipes passed in the game.
    def score
      @results.take_while { |r| r.cleared?(@pass_rate) }.size
    end

    private

    def banner
      @out.puts
      @out.puts "  FLAPPY RAILS #{Flappy::VERSION}"
      @out.puts "  >o)   #{@command.join(' ')}"
      @out.puts "        #{@times} run#{'s' unless @times == 1} per level, seed #{@seed}"
      @out.puts
    end

    def play(level, number)
      @out.puts "LEVEL #{number}: #{level.title}"
      @out.puts "  #{level.tagline}"
      @out.print "  "
      survived = 0
      failed_logs = []

      @times.times do |i|
        ok, output = run_once(level, i + 1)
        if ok
          survived += 1
          @out.print "."
        else
          @out.print "x"
          failed_logs << save_log(level, i + 1, output)
        end
        @out.flush
      end

      @out.puts "  #{survived}/#{@times} survived"
      @out.puts "  logs for crashed runs: #{@log_dir}" if failed_logs.any?
      @out.puts
      Result.new(level: level, runs: @times, survived: survived, failed_logs: failed_logs)
    end

    def run_once(level, run_number)
      env = {
        "FLAPPY_LEVEL" => level.name.to_s,
        "FLAPPY_SPEED" => @speed.to_s,
        "FLAPPY_SEED" => (@seed + run_number).to_s,
        "FLAPPY_RUN" => run_number.to_s
      }
      output, status = Open3.capture2e(env, *@command)
      @out.print "\n#{output}" if @verbose
      [status.success?, output]
    rescue SystemCallError => e
      [false, "could not start #{@command.first}: #{e.message}"]
    end

    def save_log(level, run_number, output)
      FileUtils.mkdir_p(@log_dir)
      path = File.join(@log_dir, "#{level.name}-run#{run_number}.log")
      File.write(path, output)
      path
    end

    def scoreboard
      width = @results.map { |r| r.level.title.size }.max || 10
      @out.puts "SCOREBOARD"
      @results.each_with_index do |r, i|
        verdict = r.cleared?(@pass_rate) ? "cleared" : "CRASHED"
        @out.puts format("  %<n>d  %<title>-#{width}s  %<s>3d/%<t>-3d  %<v>s", n: i + 1, title: r.level.title, s: r.survived, t: r.runs, v: verdict)
      end
      skipped = @levels.size - @results.size
      @out.puts "  (#{skipped} level#{'s' unless skipped == 1} not played)" if skipped.positive?
      @out.puts
      @out.puts "  Final score: #{score} of #{@levels.size} level#{'s' unless @levels.size == 1} cleared."
      @out.puts "  #{closing_line}"
      @out.puts
    end

    def closing_line
      case score
      when @levels.size then "Every pipe, no crashes. Your suite is built for the real world."
      when 0 then "Crashed at the first pipe. Good news: that's where the easy wins are."
      else "Down at level #{score + 1}: #{@levels[score].title}. Start with the logs."
      end
    end
  end
end
