module Masks
  module Client
    class Error < StandardError; end

    class Unreachable < Error; end

    class Rejected < Error
      attr_reader :code, :description, :status

      def initialize(code, description, status: nil)
        super([ code, description ].compact.join(": "))

        @code = code
        @description = description
        @status = status
      end
    end

    class InvalidToken < Error; end
  end
end
