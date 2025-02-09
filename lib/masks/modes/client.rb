module Masks
  module Modes
    class Client
      include Masks::Settings
      include Masks::Mode

      attr_accessor :settings

      def initialize(settings)
        self.settings = settings
      end

      def seed_client(key, **args)
        @clients ||= []
      end
    end
  end
end
