module Masks
  module Routing
    class << self
      def install!
        ActionDispatch::Routing::Mapper.include Masks::Routing::Rails
      end

      def manage_path
        @manage_path
      end

      def manage_path=(v)
        @manage_path = v
      end
    end
  end
end

require_relative "./routing/middleware"
require_relative "./routing/rails"
