module Masks
  module Client
    class Enrollment
      attr_reader :initial_access_token, :scope, :expires_in, :obtained_at

      def self.issued(body)
        if body["initial_access_token"].to_s.empty?
          raise Refused.new(
            body["error"] || "invalid_enrollment_response",
            body["error_description"] || "the enrollment endpoint answered without an initial_access_token"
          )
        end

        new(body)
      end

      def initialize(body)
        @initial_access_token = body["initial_access_token"]
        @scope = body["scope"].to_s
        @expires_in = body["expires_in"].to_i
        @obtained_at = Time.now.to_i
      end

      def expires_at
        obtained_at + expires_in
      end

      def scopes
        scope.split
      end
    end
  end
end
