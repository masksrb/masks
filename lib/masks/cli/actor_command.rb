module Masks
  module Server
    class ActorCommand < ModelCommand
      def find_model
        Masks.actors.identify(key, required: true)
      end

      def build_model
        Masks.actors.identify(key)
      end

      def preferred_keys
        %w[id key uuid name]
      end

      def settings_json
        Masks.actors.settings_json
      end
    end
  end
end
