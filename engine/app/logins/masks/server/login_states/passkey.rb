module Masks
  module Server
    module LoginStates
      class Passkey < LoginState
        FIRST_EXPIRY = 12.hours
        SECOND_EXPIRY = 12.hours
        HELD = "passkey_challenge".freeze

        accepts :passkey

        handles "passkey:challenge" do
          offer
        end

        handles "passkey:verify" do
          verify
        end

        def enabled?
          Masks::Server::Passkey.exists?
        end

        def as_json
          { "passkey" => { "offered" => offered? }.merge(challenge_json) }
        end

        def start_over!
          login.store.delete(HELD)
        end

        private

          def offered?
            login.policy.first_factor?(:passkey) || login.first_factored?
          end

          def challenge_json
            @options ? { "options" => @options } : {}
          end

          def offer
            options = relying_party.authentication_options(login.actor)

            @options = options.as_json
            login.store[HELD] = { "challenge" => options.challenge }
          end

          def verify
            held = login.store[HELD]
            return warn!("passkey-expired") if held.blank?

            presented = update(:passkey)
            return warn!("invalid-passkey") if presented.blank?

            settle(held["challenge"], JSON.parse(presented))
          ensure
            login.store.delete(HELD)
          end

          def settle(challenge, response)
            passkey = Masks::Server::Passkey.find_by(external_id: response["id"])
            if passkey.nil?
              refused! "passkey"
              return warn!("invalid-passkey")
            end

            credential = relying_party.verify_authentication(response, challenge, passkey)
            verified = !!credential.response.authenticator_data.user_verified?

            if passkey.cloned?(credential.sign_count)
              Event.record!(
                Event::LOGIN_REFUSED,
                actor: passkey.actor, by: nil, factor: "passkey", cloned: true
              )
              return warn!("invalid-passkey")
            end

            passkey.used!(credential.sign_count, user_verified: verified)

            accept(passkey, verified)
          rescue WebAuthn::Error, JSON::ParserError
            refused! "passkey"
            warn! "invalid-passkey"
          end

          def accept(passkey, verified)
            return second(passkey, verified) unless login.policy.first_factor?(:passkey)

            login.identifier = passkey.actor.identifier
            login.actor = passkey.actor

            factored! :first_factor, expiry: FIRST_EXPIRY
            login.noted! "swk"

            return unless verified

            factored! :second_factor, expiry: SECOND_EXPIRY
            login.noted! "user", "mfa"
          end

          def second(passkey, verified)
            unless verified && login.first_factored? && login.actor&.id == passkey.actor_id
              refused! "passkey"
              return warn!("factor-not-offered")
            end

            factored! :second_factor, expiry: SECOND_EXPIRY
            login.noted! "user", "mfa"
          end

          def relying_party
            RelyingParty.for(tenant, Current.origin)
          end
      end
    end
  end
end
