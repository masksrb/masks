module Masks
  module Installations
    class RailsEngine
      include Masks::Installer

      class << self
        def current
          new(Masks.env)
        end
      end

      def initialize(env)
        @settings = env.to_h.deep_stringify_keys
      end

      def setting(*args, **opts)
        @settings.dig(*args.map(&:to_s)) || opts[:default]
      end

      def modify(updates)
        @settings.deep_merge!(updates.deep_stringify_key)
      end

      def save!
        # nil
      end
    end
  end
end
