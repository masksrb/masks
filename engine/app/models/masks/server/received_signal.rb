module Masks
  module Server
    class ReceivedSignal
      class Refused < StandardError
        attr_reader :code

        def initialize(code, message)
          super(message)
          @code = code
        end
      end

      TYPE = "secevent+jwt".freeze
      MEMORY = 7.days
      SIGNED_OUT = %w[
        https://schemas.openid.net/secevent/caep/event-type/session-revoked
        https://schemas.openid.net/secevent/caep/event-type/credential-change
        https://schemas.openid.net/secevent/risc/event-type/sessions-revoked
        https://schemas.openid.net/secevent/risc/event-type/account-disabled
        https://schemas.openid.net/secevent/risc/event-type/account-purged
        https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required
      ].freeze

      attr_reader :provider, :claims

      def initialize(token, issuer:)
        @token = token.to_s.strip
        @issuer = issuer
      end

      def receive!
        @provider = sender
        @claims = verified

        audience!
        once!

        signed_out.each { |type, actors| actors.each { |actor| sign_out!(actor, type) } }

        self
      end

      private

        def unverified
          @unverified ||= JWT.decode(@token, nil, false)
        rescue JWT::DecodeError
          raise Refused.new("invalid_request", "the body is not a security event token")
        end

        def sender
          issued_by = unverified.first["iss"].to_s.chomp("/")

          Provider.active.where(protocol: Provider::OIDC, receives_signals: true).find_by(issuer: issued_by) ||
            raise(Refused.new("invalid_issuer", "no provider here sends signals as #{issued_by.truncate(100)}"))
        end

        def verified
          held, header = provider.federation.verify_signed(@token)

          raise Refused.new("invalid_request", "a security event token is typed #{TYPE}") unless header["typ"].to_s.casecmp?(TYPE)
          raise Refused.new("invalid_request", "a security event token carries events") unless held["events"].is_a?(Hash)

          held
        rescue Provider::Untrusted, Provider::Refused, Provider::Unreachable => e
          raise Refused.new("invalid_key", e.message)
        end

        def audience!
          accepted = [ @issuer.url, "#{@issuer.url}/ssf/events" ]

          return if Array(claims["aud"]).intersect?(accepted)

          raise Refused.new("invalid_audience", "that security event token is meant for another receiver")
        end

        def once!
          jti = claims["jti"].to_s

          raise Refused.new("invalid_request", "a security event token carries a jti") if jti.empty?
          return if Replay.first?("signal", jti, within: provider.id, expires_in: MEMORY)

          raise Refused.new("invalid_request", "that security event token has already been received")
        end

        def signed_out
          claims["events"].slice(*SIGNED_OUT).to_h do |type, body|
            subject = (body.is_a?(Hash) && body["subject"]) || claims["sub_id"]

            [ type, accounts(subject) ]
          end
        end

        def accounts(subject)
          return [] unless subject.is_a?(Hash)

          connections =
            case subject["format"] || subject["subject_type"]
            when "iss_sub", "iss-sub"
              return [] unless subject["iss"].to_s.chomp("/") == provider.issuer

              Connection.live.where(provider: provider, subject: subject["sub"].to_s)
            when "email"
              Connection.live.where(provider: provider, email: subject["email"].to_s.downcase)
            else
              Connection.none
            end

          Actor.where(id: connections.select(:actor_id)).to_a
        end

        def sign_out!(actor, type)
          actor.sign_out_everywhere!

          Event.record!(Event::SIGNAL_RECEIVED, actor: actor, by: nil, provider: provider.key,
                                                event: type, jti: claims["jti"])
        end
    end
  end
end
