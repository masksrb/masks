module Masks
  module Server
    class ClientCommand < ModelCommand
      def preferred_keys
        %w[id key name]
      end

      def find_model
        Masks.clients.discover(key)
      end

      def build_model
        Masks::Client.seed(key:, **updates)
      end

      def settings_json
        Masks::Client.settings_json
      end

      def settings_spec
        super.merge(
          types:
            Masks
              .conf
              .client_types
              .map do |type, json|
                [
                  type,
                  {
                    desc: I18n.t("settings.masks/client.types.#{type}"),
                    settings: {
                    }, # TODO
                    json: JSON.pretty_generate(json),
                  },
                ]
              end
              .to_h,
        )
      end
    end
  end
end
