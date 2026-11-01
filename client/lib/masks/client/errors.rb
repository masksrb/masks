module Masks
  module Client
    def self.failure(key, *values)
      code, template = FAILURES.fetch(key.to_sym)

      [ code, format(template, *values) ]
    end

    def self.saying(key, *values)
      failure(key, *values).last
    end

    def self.worded(code, description)
      [ "masks", code, description ].reject { |part| part.to_s.empty? }.join(": ")
    end

    class Error < StandardError
      attr_reader :code, :description, :status, :uri

      def initialize(code, description = nil, status: nil, uri: nil)
        @code = code.to_s
        @description = description
        @status = status
        @uri = uri

        super(Masks::Client.worded(@code, description))
      end
    end

    class Refused < Error
      def self.of(key, *values)
        new(*Masks::Client.failure(key, *values))
      end
    end

    class Unregistered < Refused
      CODE = "invalid_client".freeze

      def self.raised_by?(body)
        body["error"].to_s == CODE
      end
    end

    class InvalidToken < Error
      def self.of(key, *values)
        code, description = Masks::Client.failure(key, *values)

        new(description, code: code, missing: key.to_s == "no_token")
      end

      def initialize(description, code: "invalid_token", missing: false, dpop: nil)
        @missing = missing
        @dpop = dpop.nil? ? code == "invalid_dpop_proof" : dpop

        super(code, description, status: 401)
      end

      def missing?
        @missing
      end

      def dpop?
        @dpop
      end
    end

    class Forbidden < Error
      attr_reader :scope

      def self.of(key, *values)
        new(*Masks::Client.failure(key, *values))
      end

      def initialize(code, description, scope: nil)
        @scope = scope

        super(code, description, status: 403)
      end
    end

    class Unavailable < Error
      def self.of(key, *values)
        new(Masks::Client.saying(key, *values))
      end

      def initialize(description)
        super("temporarily_unavailable", description, status: 503)
      end
    end

    class Insecure < Error
      def self.of(key, *values)
        new(Masks::Client.saying(key, *values))
      end

      def initialize(description)
        super("insecure_url", description)
      end
    end

    class Foreign < Error
      def self.of(key, *values)
        new(Masks::Client.saying(key, *values))
      end

      def initialize(description)
        super("foreign_origin", description)
      end
    end
  end
end
