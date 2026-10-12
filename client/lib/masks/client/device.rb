module Masks
  module Client
    class Device
      GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code".freeze
      INTERVAL = 5
      REQUIRED = %w[device_code user_code verification_uri].freeze

      attr_reader :device_code, :user_code, :verification_uri, :verification_uri_complete, :expires_in, :interval,
                  :obtained_at

      def self.issued(body)
        missing = REQUIRED.find { |field| body[field].to_s.empty? }

        if missing
          raise Rejected.new(
            body["error"] || "invalid_device_authorization_response",
            body["error_description"] || "the device authorization endpoint answered without a #{missing}"
          )
        end

        new(body)
      end

      def initialize(body)
        @device_code = body["device_code"]
        @user_code = body["user_code"]
        @verification_uri = body["verification_uri"]
        @verification_uri_complete = body["verification_uri_complete"]
        @expires_in = body["expires_in"].to_i
        @interval = body["interval"].to_i
        @obtained_at = Time.now.to_i
      end

      def expires_at
        obtained_at + expires_in
      end

      def expired?
        Time.now.to_i > expires_at
      end

      def inspect
        "#<#{self.class.name} #{user_code} for #{verification_uri}>"
      end
    end
  end
end
