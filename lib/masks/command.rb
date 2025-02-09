require "active_support/all"
require "colorize"
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

    def help(&block)
      if block_given?
        @help = block
      elsif @help
        instance_exec(&@help)
      else
        puts opts
      end
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

          return print_help if options[:help]

          instance_exec(&@runner) if @runner
        end
    end

    def options
      @options ||= {}
    end

    def thor
      @thor ||= Thor::Base.shell.new
    end

    delegate :print_table, :set_color, :say_status, :say, to: :thor

    def print_header(*args, separator: false, margin: true)
      puts if margin
      say_status(*args)
      say_status("", "—" * args[1].length) if separator
      puts if margin
    end

    def print_settings(settings, name = "setting")
      any_env = false

      table =
        settings.map do |name, setting|
          [
            name,
            setting[:env] || setting[:env_only],
            setting[:default],
            setting[:desc],
          ]
        end

      heading = [name, (any_env ? "env var" : ""), "default", "description"]

      print_table(
        [heading, heading.map { |s| s.gsub(/./, "-") }, *table],
        indent:,
      )
    end

    def print_model(model, keys = nil, indent: nil)
      settings = model.class.settings_json

      table =
        (keys || settings.keys).map do |key|
          conf = settings.dig(key.to_s)

          if conf && conf[:writer]
            [key, attrs.stringify_keys[key]]
          else
            value = JSON.generate(model.setting(key))

            if conf && conf[:secret]
              [key, filter_value(key, value)]
            else
              [key, value]
            end
          end
        rescue => e
          [key, nil]
        end

      print_table(table, indent:)
    end

    def print_help
      help
      exit
    end

    def default_name
      self.class.name.split("::").last.underscore.gsub(/_command/, "")
    end

    def default_desc
      i18n("desc")
    end

    def i18n(key)
      unless @loaded
        I18n.load_path += Dir[Masks::SRC.join("config", "locales", "*.{yml}")]
        @loaded = true
      end

      I18n.t("masks.command.#{name}.#{key}")
    end

    def opts
      @opts ||=
        OptionParser.new do |opts|
          opts.on "-h", "--help", "Print help and exit" do
            options[:help] = true
          end
        end
    end
  end
end
