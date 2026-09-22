module Masks
  module Server
    class ClientAssertion
      class Refused < StandardError; end

      TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
      SUBJECT = "that client assertion".freeze

      attr_reader :token

      def self.issuer_of(token)
        claims = JWT.decode(token.to_s, nil, false).first

        claims["sub"].presence || claims["iss"].presence
      rescue JWT::DecodeError
        nil
      end

      def initialize(token, client:, audiences:)
        @token = token.to_s
        @client = client
        @audiences = Array(audiences).map { |one| one.to_s.chomp("/") }
      end

      def verify!
        keys = ClientKeys.new(client)
        claims, = keys.decode(token, subject: SUBJECT)

        named!(claims)
        addressed!(claims)
        keys.timely!(claims, subject: SUBJECT)

        raise Refused, "a client assertion must carry a jti" if claims["jti"].blank?

        keys.once!(claims, kind: "client-assertion", subject: SUBJECT)

        self
      rescue ClientKeys::Refused => e
        raise Refused, e.message
      end

      private

        attr_reader :client, :audiences

        def named!(claims)
          unless claims["iss"] == client.client_id && claims["sub"] == client.client_id
            raise Refused, "a client assertion must name the client as both iss and sub"
          end
        end

        def addressed!(claims)
          named = Array(claims["aud"]).map { |one| one.to_s.chomp("/") }

          raise Refused, "that client assertion was made for another audience" if (named & audiences).empty?
        end
    end
  end
end
