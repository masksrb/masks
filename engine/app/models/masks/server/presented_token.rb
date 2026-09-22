module Masks
  module Server
    class PresentedToken
      ACCESS_TOKEN = "urn:ietf:params:oauth:token-type:access_token".freeze
      ID_TOKEN = "urn:ietf:params:oauth:token-type:id_token".freeze
      TYPES = [ ACCESS_TOKEN, ID_TOKEN ].freeze

      attr_reader :type, :claims

      def self.read(token, type:, issuer:)
        held = new(token, type: type, issuer: issuer)

        held.claims ? held : nil
      end

      def initialize(token, type:, issuer:)
        @token = token.to_s
        @type = type.to_s
        @issuer = issuer
        @claims = decode
      end

      def access_token?
        type == ACCESS_TOKEN
      end

      def id_token?
        type == ID_TOKEN
      end

      def record
        return @record if defined?(@record)

        @record = access_token? ? AccessToken.live.find_by(digest: claims["jti"]) : nil
      end

      def live?
        access_token? ? record.present? : session_live?
      end

      def actor
        return @actor if defined?(@actor)

        @actor = access_token? ? record&.actor : Subjects.locate(claims["sub"])
      end

      def subject
        claims["sub"]
      end

      def held_by?(client)
        return record&.client_id == client.id if access_token?

        Array(claims["aud"]).include?(client.client_id) && (claims["azp"].blank? || claims["azp"] == client.client_id) &&
          actor.present? && issuer.subject_for(actor, client) == subject
      end

      def scope_list
        access_token? ? record.scope_list : []
      end

      def audience
        access_token? ? record.audience : []
      end

      def expires_at
        access_token? ? record.expires_at : Time.zone.at(claims["exp"].to_i)
      end

      def act
        claims["act"]
      end

      def client_id
        access_token? ? record&.client&.client_id : Array(claims["aud"]).first
      end

      private

        attr_reader :token, :issuer

        def decode
          case type
          when ACCESS_TOKEN then AccessToken.decode(token, issuer: issuer)
          when ID_TOKEN then id_token_claims
          end
        rescue JWT::DecodeError
          nil
        end

        def id_token_claims
          claims = issuer.verify(token, typ: "jwt", required: %w[iss sub aud exp])

          raise JWT::DecodeError, "that token is not an id token" if claims.key?("jti") || claims.key?("events")

          claims
        end

        def session_live?
          return actor.present? if claims["sid"].blank?

          Session.live.exists?(uuid: claims["sid"], actor_id: actor&.id)
        end
    end
  end
end
