module Masks
  module Server
    module LoginStates
      class Identifier < LoginState
        accepts :identifier

        def reload!
          login.identifier ||= session&.actor&.identifier
        end

        handles "identify" do
          login.identifier = update(:identifier)

          warn! "missing-identifier" if login.identifier.blank?

          discover
        end

        handles "start-over" do
          login.start_over!
        end

        prompts "identify" do
          login.identifier.blank? && !login.first_factored? && !login.first_run?
        end

        def as_json
          {
            "signupOpen" => login.policy.signup && login.policy.local?,
            "identifies" => %i[password passkey email_code].any? { |factor| login.policy.first_factor?(factor) }
          }
        end

        def start_over!
          login.identifier = nil
        end

        private

          def discover
            provider = Masks::Server::DomainClaim.for_email(login.identifier)&.discovers

            login.state("provider").discover!(provider) if provider
          end
      end
    end
  end
end
