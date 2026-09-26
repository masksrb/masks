module Masks
  module Server
    module LoginStates
      class CodeFactor < LoginState
        HELD = "code_factor".freeze

        accepts :factor, :code, :remember

        handles "code:send", limit: :sending do
          send_code
        end

        handles "code:verify", limit: :verifying do
          verify
        end

        def enabled?
          actor.present? && held_factors.any?
        end

        def held_factors
          CodeFactors::FACTORS.select do |factor|
            CodeFactors.held?(actor, factor) && (actor.manages? || login.policy.second_factor?(factor))
          end
        end

        def usable_factors
          held_factors.select do |factor|
            CodeFactors.deliverable?(factor) && (factor != "email" || independent_of_the_inbox?)
          end
        end

        def withheld
          held_factors.include?("email") && !independent_of_the_inbox? ? [ "email" ] : []
        end

        def as_json
          {
            "codeFactors" => usable_factors.to_h { |factor| [ factor, CodeFactors.masked(actor, factor) ] },
            "codeSent" => sent_json,
            "codesWithheld" => withheld.presence
          }.compact
        end

        def start_over!
          login.store.delete(HELD)
        end

        private

          def independent_of_the_inbox?
            login.amr.intersect?(CodeFactors::INDEPENDENT_OF_THE_INBOX)
          end

          def held
            stored = login.store[HELD]

            stored.present? && stored["actor_id"] == actor.id ? stored : {}
          end

          def token
            return @token if defined?(@token)

            @token = CodeFactors.sent(actor, held["factor"], held["token_id"])
          end

          def sent_json
            return nil if held["factor"].blank? || token.nil?

            { "factor" => held["factor"], "to" => CodeFactors.masked(actor, held["factor"]),
              "resendable" => token.resendable? }
          end

          def send_code
            return warn!("missing-first-factor") unless login.first_factored?

            factor = update(:factor).to_s
            return warn!("factor-not-offered") unless usable_factors.include?(factor)
            return if held["factor"] == factor && token && !token.resendable?

            sent = CodeFactors.send!(actor, factor)

            remove_instance_variable(:@token) if defined?(@token)
            login.store[HELD] = { "actor_id" => actor.id, "factor" => factor, "token_id" => sent.id }
          end

          def verify
            return warn!("missing-first-factor") unless login.first_factored?

            factor = held["factor"]
            return warn!("confirmation-expired") if token.nil? || !usable_factors.include?(factor)

            if token.verify(update(:code))
              login.store.delete(HELD)
              remove_instance_variable(:@token)
              factored! :second_factor, expiry: OneTimePassword::EXPIRY
              remember! DeviceFactor::SECOND_FACTOR if remembering?
              login.noted! CodeFactors.amr(factor), "mfa"
            else
              remove_instance_variable(:@token)
              refused! "#{factor}_code"
              warn! "invalid-code"
            end
          end

          def remembering?
            device.present? && ActiveModel::Type::Boolean.new.cast(update(:remember))
          end
      end
    end
  end
end
