module Masks
  module Server
    module LoginStates
      class RiskCheck < LoginState
        HELD = "risk".freeze
        BREACHED = "breached".freeze

        def enabled?
          actor.present? && touched?(:first_factor) && assessing?
        end

        def factor!
          return unless enabled?

          assess! unless assessed?

          refuse_risky! if refusing?
        end

        def stepping_up?
          enabled? && assessed? && threshold(:risk_step_up_at)&.then { |at| score >= at }
        end

        def start_over!
          login.store.delete(HELD)
          login.store.delete(BREACHED)
        end

        private

          def assessing?
            policy = login.policy

            policy.risk_step_up_at.present? || policy.risk_refuse_at.present?
          end

          def threshold(name)
            login.policy.public_send(name)
          end

          def score
            login.store.dig(HELD, "score").to_i
          end

          def stamp
            login.factored_at(:first_factor)&.iso8601(Login::PRECISION)
          end

          def assessed?
            login.store.dig(HELD, "at") == stamp
          end

          def refusing?
            (at = threshold(:risk_refuse_at)) && score >= at
          end

          def assess!
            risk = Risk.new(actor: actor, device: device, ip_address: Current.ip_address, breached: login.store[BREACHED] == true)

            login.store[HELD] = { "at" => stamp, "score" => risk.score, "signals" => risk.signals }

            return if risk.score.zero?

            Event.record!(Event::SIGN_IN_RISKY, actor: actor, by: nil, score: risk.score, signals: risk.signals,
                                                refused: refusing?, stepped_up: !refusing? && stepping_up?)
          end

          def refuse_risky!
            expire! :first_factor

            Event.record!(Event::LOGIN_REFUSED, actor: actor, by: nil, factor: "risk", score: score)

            warn! "risky-sign-in"
          end
      end
    end
  end
end
