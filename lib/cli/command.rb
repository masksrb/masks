require "active_support/all"
require "optparse"
require "shellwords"
require "thor"

module Masks
  class << self
    def cli(&block)
      @cli ||= Command.new(&block)
    end

    def cmd(&block)
      Command.new(&block)
    end

    def cmd!(&block)
      Command.new(&block).tap { |c| c.run! }
    end
  end

  class Command
    def initialize(&block)
      instance_exec(&block)
    end

    def subcommand
      @subcommand ||= (@cmds&.fetch(ARGV[0], nil) if ARGV[0])
    end

    def run(&block)
      @runner = block
    end

    def cmd(cmd = nil, &block)
      @cmds ||= {}

      if cmd || block
        cmd ||= self.class.new(&block)
        @cmds[cmd.name] = cmd
      end

      @cmds
    end

    def name(*args)
      @name = args[0] if args.any?

      @name
    end

    def desc(*args)
      opts.banner = ""

      @desc ||= []

      @desc << args.join(" ") if args.any?

      @desc.join("\n\n")
    end

    def help
      puts opts
    end

    def on(*args, **opts, &block)
      cli = self

      self.opts.on(*args, **opts) { cli.instance_exec(&block) }
    end

    def run!
      return if @has_run

      @has_run = true

      @run ||=
        if subcommand
          subcommand.run!
        else
          opts.order!
          opts.parse!

          instance_exec(&@runner)
        end
    end

    def options
      @options ||= {}
    end

    def thor
      @thor ||= Thor::Base.shell.new
    end

    delegate :print_table, :set_color, :say_status, :say, to: :thor

    def print_header(*args, separator: false)
      puts
      say_status(*args)
      say_status("", "—" * args[1].length) if separator
      puts
    end

    def print_help
      help
      exit
    end

    def opts
      @opts ||=
        OptionParser.new do |opts|
          opts.on "-h", "--help", "Print help and exit" do
            print_help
          end
        end
    end
  end
end
