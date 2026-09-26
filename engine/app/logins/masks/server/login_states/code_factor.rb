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
          CodeFactors::FACTORS.select { |factor| CodeFactors.held?(actor, factor) }
        end

        def usable_factors(held = held_factors)
          held.select { |factor| CodeFactors.deliverable?(factor) && !withheld?(factor) }
        end

        def as_json
          held = held_factors

          {
            "codeFactors" => usable_factors(held).to_h { |factor| [ factor, CodeFactors.masked(actor, factor) ] },
            "codeSent" => sent_json,
            "codesWithheld" => held.select { |factor| withheld?(factor) }.presence
          }.compact
        end

        def start_over!
          login.store.delete(HELD)
        end

        private

          def withheld?(factor)
            factor == "email" && !login.amr.intersect?(CodeFactors::INDEPENDENT_OF_THE_INBOX)
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
            return nil if token.nil?

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
              second_factored! CodeFactors.amr(factor)
            else
              remove_instance_variable(:@token)
              refused! "#{factor}_code"
              warn! "invalid-code"
            end
          end
      end
    end
  end
end
