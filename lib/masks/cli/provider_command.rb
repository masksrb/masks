module Masks
  module Server
    class ProviderCommand < ModelCommand
      def help_notes
        super

        puts
        say_status "", "Available types:"
        puts

        Masks.conf.provider_map.each do |key, cls|
          say_status key, "", :blue
          print_settings(cls.settings_json)
          puts
        end

        nil
      end

      def preferred_keys
        %w[id key name]
      end

      def extra_keys
        %w[assign_client remove_client]
      end

      def settings_json
        @model&.class&.settings_json || Masks::Provider.settings_json
      end

      def find_model
        @model ||= Masks.provider(key)
      end

      def build_model
        @model ||= Masks::Provider.seed(key:, **attrs)
      end

      def settings_spec
        super.merge(
          types:
            Masks
              .conf
              .provider_types
              .keys
              .map do |type|
                proto = Masks::Provider.new(type:)

                [
                  type,
                  {
                    name: proto.name,
                    settings: proto.type_class.settings_json,
                  },
                ]
              end
              .to_h,
        )
      end
    end
  end
end
