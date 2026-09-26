module Masks
  module Server
    module LoginStates
      class SecondFactor < LoginState
        def enabled?
          actor.present? && (actor.second_factor? || codes.enabled?)
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
              "email" => codes.usable_factors.include?("email"),
              "sms" => codes.usable_factors.include?("sms")
            },
            "rememberable" => device.present?,
            "trustFor" => ActionController::Base.helpers.distance_of_time_in_words(DeviceFactor::LIFETIME)
          }
        end

        def start_over!
          expire! :second_factor
        end

        private

          def codes
            login.state("code-factor")
          end
      end
    end
  end
end
