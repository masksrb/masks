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

    class Unregistered < Rejected
      CODE = "invalid_client".freeze

      def self.raised_by?(body)
        body["error"].to_s == CODE
      end
    end

    class InvalidToken < Error; end

    class Challenge < Error
      attr_reader :code, :description, :status, :scope

      def initialize(code, description, status:, scope: nil)
        super([ code, description ].compact.join(": "))

        @code = code
        @description = description
        @status = status
        @scope = scope
      end
    end

    class Unauthenticated < Challenge
      def initialize(description = "a bearer token is required", code: nil)
        super(code, description, status: 401)
      end
    end

    class Unauthorized < Challenge
      def initialize(description, code: "invalid_token")
        super(code, description, status: 401)
      end
    end

    class Forbidden < Challenge
      def initialize(code, description, scope: nil)
        super(code, description, status: 403, scope: scope)
      end
    end
  end
end
