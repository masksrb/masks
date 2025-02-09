module Masks
  module Errors
    class AuthError < RuntimeError
      def code
        self
          .class
          .name
          .delete_suffix("Error")
          .split("::")
          .last
          .underscore
          .dasherize
      end
    end

    class InvalidConf < RuntimeError
    end

    class InvalidMode < RuntimeError
      def initialize(mode)
        if mode
          super "Invalid mode: #{mode}"
        else
          super "Specify a mode for masks: server | client"
        end
      end
    end

    class MissingClient < AuthError
    end
  end
end
