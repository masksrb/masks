module Masks
  module Server
    module LoginStates
      class Inbox < LoginState
        HELD = "inbox".freeze

        accepts :code

        handles "inbox:verify", limit: :verifying do
          verify
        end

        handles "inbox:resend", limit: :sending do
          send_code if resendable?
        end

        prompts "prove-email" do
          open!
          true
        end

        def enabled?
          pending?
        end

        def pending?
          hiding? && !proven? && !passed?
        end

        def proven?(identifier = login.identifier)
          address = self.class.address(identifier)

          address.present? && held["proven"] == address
        end

        def as_json
          {
            "inbox" => {
              "email" => address,
              "mails" => ActorMailer.deliverable?,
              "resendable" => resendable?
            }
          }
        end

        def start_over!
          login.store.delete(HELD)
        end

        def cleanup!
          proven = login.store.dig(HELD, "proven")
          owner = login.actor

          return if proven.blank? || owner.nil? || owner.email_verified_at.present? || !login.first_factored?
          return unless owner.email.to_s.casecmp?(proven)

          owner.update!(email_verified_at: Time.current)

          Event.record!(Event::EMAIL_VERIFIED, actor: owner)
        end

        def self.address(identifier)
          held = identifier.to_s.strip.downcase

          held.include?("@") ? held : nil
        end

        private

          def hiding?
            login.policy.hidden && !login.first_run? && address.present?
          end

          def passed?
            located = named

            located.present? &&
              ((login.first_factored? && login.actor&.id == located.id) ||
               session&.actor&.id == located.id ||
               (device.present? && DeviceFactor.live.exists?(device: device, actor: located)))
          end

          def named
            return @named[address] if @named&.key?(address)

            (@named ||= {})[address] = Masks::Server::Actor.locate(address)
          end

          def address
            self.class.address(login.identifier)
          end

          def held
            stored = login.store[HELD]

            stored.present? && stored["address"] == address ? stored : {}
          end

          def token
            return @token if defined?(@token)

            id = held["token_id"]
            found = id && Masks::Server::ConfirmationCode.inbox.find_by(id: id)

            @token = found&.live? && found.address == address ? found : nil
          end

          def resendable?
            token&.resendable? != false
          end

          def open!
            return unless ActorMailer.deliverable?
            return if token || held["sent"].present?

            send_code
          end

          def send_code
            remove_instance_variable(:@token) if defined?(@token)

            if Masks::Server::ConfirmationCode.inbox_crowded?(address: address, ip: Current.ip_address)
              login.store[HELD] = { "address" => address, "sent" => Time.current.to_i }
              return warn!("too-many-codes")
            end

            opened, code = Masks::Server::ConfirmationCode.open_inbox!(address: address, ip: Current.ip_address)

            ActorMailer.confirmation_code(address, code, tenant_name: tenant&.name).deliver_later

            login.store[HELD] = { "address" => address, "token_id" => opened.id, "sent" => Time.current.to_i }
          end

          def verify
            return unless hiding?
            return warn!("confirmation-expired") if token.nil?

            unless token.verify(update(:code)) && token.address == address
              remove_instance_variable(:@token)
              refused! "inbox"
              return warn!("invalid-code")
            end

            login.store[HELD] = { "address" => address, "proven" => address }

            settle
          end

          def settle
            reveal_absence if named.nil? && !login.state("signup").enabled?
          end

          def reveal_absence
            login.identifier = nil
            login.store.delete(HELD)

            warn! "no-account-for-email"
          end
      end
    end
  end
end
