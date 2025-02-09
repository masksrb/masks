module Masks
  class ModelCommand < Masks::Command
    def initialize
      super do
        name default_name
        desc default_desc

        on "--show-secrets", "-S", "Show secrets" do
          ENV["SHOW_SECRETS"] = "true"
        end

        on "--spec", "Output spec as JSON" do
          options[:spec] = true
        end

        run { handle }
      end
    end

    def key
      @key ||= ARGV[1] if ARGV[1]&.match?(/^\w+$/)
    end

    def updates
      @updates ||=
        attrs
          .map do |k, v|
            conf = settings_json[k.to_s]

            if conf
              [k, conf[:cast].call(v)] if !conf[:readonly]
            end
          end
          .compact
          .to_h
    end

    def attrs
      @attrs ||=
        (ARGV.slice(1...) || [])
          .map do |attr|
            if attr.include?("=")
              name, value = attr.split("=", 2)

              [name, value]
            end
          end
          .compact
          .to_h
          .symbolize_keys
    end

    def handle
      return json_help if options[:spec]
      return help if !key

      model = find_model

      keys =
        if updates.keys.any?
          model ||= build_model

          updates.each { |k, v| model.send("#{k}=", v) }

          created = model.new_record?

          model.save!

          say_status name, "'#{key}' #{created ? "created" : "saved"}..."

          if created
            ["key", *setting_keys].uniq
          else
            changed = attrs.keys.map(&:to_s) & settings_json.keys

            ["key", *changed].uniq
          end
        elsif model
          say_status name, "#{key}"

          ["id", "key", *setting_keys].uniq
        else
          say_status name, "not found...", :red

          return
        end

      table =
        keys.map do |key|
          conf = settings_json.dig(key.to_s)

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
    rescue ActiveRecord::RecordInvalid
      model.errors.full_messages.each { |msg| say_status name, msg, :red }
    rescue => e
      say_status name, e.to_s, :red

      puts e.backtrace
    end

    def settings_spec
      { name: name.titleize, settings: settings_json }
    end

    private

    def extra_keys
      []
    end

    def filter_value(key, value)
      return value if ENV["SHOW_SECRETS"]

      "[FILTERED]"
    end

    def json_help
      puts JSON.pretty_generate(settings_spec)
    end

    def help
      return json_help if options[:spec]

      header = ["[key] [...setting=value]", i18n("help")].join("\n\n")

      say_status name, header

      print_settings(settings_json)

      notes = help_notes

      if notes
        puts
        say_status "note", notes
        puts
      end
    end

    def help_notes
      # Nothing by default
    end

    def find_model
      raise NotImplementedError
    end

    def build_model
      raise NotImplementedError
    end

    def settings_json
      {}
    end

    def setting_keys
      [*preferred_keys, *settings_json.keys.map(&:to_s)].uniq
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

    def preferred_keys
      []
    end

    def indent
      12 - name.length
    end
  end
end
