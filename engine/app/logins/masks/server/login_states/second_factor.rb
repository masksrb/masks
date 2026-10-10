module Masks
  module Server
    module LoginStates
      class SecondFactor < LoginState
        def enabled?
          actor.present? && (actor.second_factor? || codes.enabled?)
        end

        handles "recovery:request", limit: :sending do
          request_recovery
        end

        prompts "second-factor" do
          login.first_factored? && !login.second_factored?
        end

        def factor!
          login.noted! "mfa" if enabled? && remembered?(DeviceFactor::SECOND_FACTOR)

          super
        end

        def as_json
          {
            "secondFactors" => {
              "otp" => actor.otp?,
              "passkey" => actor.verified_passkeys?,
              "trustedDevice" => login.state("trusted-device").offered?
            },
            "rememberable" => device.present?,
            "recovery" => { "requested" => actor.recovery_requested_at.present? },
            "trustFor" => ActionController::Base.helpers.distance_of_time_in_words(DeviceFactor::LIFETIME)
          }
        end

        def start_over!
          expire! :second_factor
        end

        private

          def request_recovery
            return warn!("missing-first-factor") unless login.first_factored? && !login.second_factored?

            HelpRequests.request!(actor, journey: Masks::Server::Journey.sign_in(login))
            false
          end

          def codes
            login.state("code-factor")
          end
      end
    end
  end
end
