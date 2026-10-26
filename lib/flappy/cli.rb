require "optparse"
require "flappy"

module Flappy
  class CLI
    HELP = <<~TEXT
      Flappy Rails #{Flappy::VERSION}: can your test suite make it through the pipes?

      Usage:
        flappy run [options] -- COMMAND...     run COMMAND repeatedly, level by level
        flappy pipe --to HOST:PORT [options]   run a flaky pipe in front of HOST:PORT
        flappy levels                          list the levels
        flappy version

      run options:
        --levels LIST      level numbers or names, comma separated (default: all)
        --times N          runs per level (default: 10)
        --speed X          play the weather X times faster (default: 1)
        --seed N           seed for repeatable randomness
        --sudden-death     stop at the first level that crashes
        --pass-rate P      share of runs that must pass, 0 to 1 (default: 1)
        --log-dir DIR      where crashed run output is saved (default: tmp/flappy)
        --verbose          print each run's output

      pipe options:
        --to HOST:PORT     where to send traffic (required)
        --listen PORT      port to listen on (default: any free port)
        --bind HOST        address to listen on (default: 127.0.0.1)
        --level NAME       play a level on a loop
        --speed X          play the level X times faster
        --latency MS  --jitter MS  --up-kbps N  --down-kbps N  --reset PERCENT
        --stall  --offline      fixed conditions when no level is given
    TEXT

    def self.start(argv, out: $stdout, err: $stderr)
      new(out: out, err: err).start(argv)
    end

    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def start(argv)
      command, *rest = argv
      case command
      when "run" then run(rest)
      when "pipe" then pipe(rest)
      when "levels" then levels
      when "version", "--version", "-v" then @out.puts(Flappy::VERSION) || 0
      when nil, "help", "--help", "-h" then @out.puts(HELP) || 0
      else
        @err.puts "flappy: unknown command #{command.inspect}\n\n#{HELP}"
        2
      end
    rescue Flappy::Error, OptionParser::ParseError => e
      @err.puts "flappy: #{e.message}"
      2
    end

    private

    def levels
      Flappy.levels.each_with_index do |l, i|
        @out.puts format("  %<n>d  %<name>-11s %<title>-18s %<tagline>s", n: i + 1, name: l.name, title: l.title, tagline: l.tagline)
      end
      0
    end

    def run(args)
      options = { times: 10, speed: 1.0, levels: Levels::ALL }
      flags, command = split_command(args)
      OptionParser.new do |o|
        o.on("--levels LIST") { |v| options[:levels] = v.split(",").map(&:strip) }
        o.on("--times N", Integer) { |v| options[:times] = v }
        o.on("--speed X", Float) { |v| options[:speed] = v }
        o.on("--seed N", Integer) { |v| options[:seed] = v }
        o.on("--sudden-death") { options[:sudden_death] = true }
        o.on("--pass-rate P", Float) { |v| options[:pass_rate] = v }
        o.on("--log-dir DIR") { |v| options[:log_dir] = v }
        o.on("--verbose") { options[:verbose] = true }
      end.parse!(flags)

      raise Flappy::Error, "give flappy a command to run, after --  (for example: flappy run -- bin/rails test)" if command.empty?

      Runner.new(command: command, out: @out, **options.compact).run ? 0 : 1
    end

    def pipe(args)
      options = { conditions: {} }
      OptionParser.new do |o|
        o.on("--to HOST:PORT") { |v| options[:to] = v }
        o.on("--listen PORT", Integer) { |v| options[:port] = v }
        o.on("--bind HOST") { |v| options[:host] = v }
        o.on("--level NAME") { |v| options[:level] = v }
        o.on("--speed X", Float) { |v| options[:speed] = v }
        o.on("--latency MS", Integer) { |v| options[:conditions][:latency] = v }
        o.on("--jitter MS", Integer) { |v| options[:conditions][:jitter] = v }
        o.on("--up-kbps N", Integer) { |v| options[:conditions][:up_kbps] = v }
        o.on("--down-kbps N", Integer) { |v| options[:conditions][:down_kbps] = v }
        o.on("--reset PERCENT", Float) { |v| options[:conditions][:reset_chance] = v / 100.0 }
        o.on("--stall") { options[:conditions][:stall] = true }
        o.on("--offline") { options[:conditions][:offline] = true }
      end.parse!(args)

      raise Flappy::Error, "--to HOST:PORT is required" unless options[:to]

      pipe_options = { to: options[:to], conditions: Conditions.new(**options[:conditions]) }
      pipe_options[:port] = options[:port] if options[:port]
      pipe_options[:host] = options[:host] if options[:host]
      pipe_options[:on_event] = ->(event, *payload) { announce(event, payload.first) }

      pipe = Flappy.pipe(**pipe_options)
      player = options[:level] ? Flappy.level(options[:level]).play(pipe, speed: options.fetch(:speed, 1.0)) : nil
      @out.puts "Flappy pipe listening on #{pipe.url}, sending to #{pipe.to_host}:#{pipe.to_port}"
      @out.puts "Playing #{player.level.title}. Ctrl-C to stop." if player
      wait_for_interrupt
      player&.stop
      pipe.stop
      @out.puts "stats: #{pipe.stats}"
      0
    end

    def announce(event, payload)
      case event
      when :conditions then @out.puts "  #{Time.now.strftime('%H:%M:%S')}  #{payload.describe}"
      when :reset then @out.puts "  #{Time.now.strftime('%H:%M:%S')}  connection reset"
      end
    end

    def wait_for_interrupt
      stop = false
      trap("INT") { stop = true }
      trap("TERM") { stop = true }
      sleep(0.1) until stop
    end

    # Everything before `--` is flags, everything after is the command.
    def split_command(args)
      index = args.index("--")
      return [args, []] unless index

      [args[0...index], args[(index + 1)..]]
    end
  end
end
