module Masks
  class ConfCommand < ModelCommand
    def help_header
      <<-HELP
    Shows configuration for this masks installation.

    If the installation is writable, you will be
    able to customize settings:

    $ masks conf setting=...
    HELP
    end

    def key
      Masks.conf.name
    end

    def find_model
      Masks.conf
    end

    def attrs
      if Masks.conf.writable?
        super
      else
        {}
      end
    end

    def settings_json
      Masks.conf.class.settings_json
    end

    def settings_spec
      settings = Masks::Modes::Client.settings_json
      server = Masks::Modes::Server.settings_json.except(*settings.keys)

      super.merge(
        name: "masks",
        settings:,
        types: {
          server: {
            name: "Server",
            settings: server,
          },
        },
      )
    end

    def preferred_keys
      %w[name url]
    end
  end
end
