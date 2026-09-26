module Masks
  module Server
    module LoginStates
      class TrustedDevice < LoginState
        HELD = "trusted_device".freeze

        accepts :remember

        handles "approval:request", limit: :sending do
          request_approval
        end

        handles "approval:check" do
          check
        end

        def enabled?
          actor.present? && login.first_factored? && !login.second_factored? && offered?
        end

        def offered?
          login.policy.second_factor?("trusted_device") &&
            SignInApproval.approvers?(actor: actor, except: device)
        end

        def as_json
          { "approval" => approval_json }.compact
        end

        def start_over!
          login.store.delete(HELD)
        end

        private

          def held
            stored = login.store[HELD]

            stored.present? && stored["actor_id"] == actor.id ? stored : {}
          end

          def approval
            return @approval if defined?(@approval)

            id = held["token_id"]
            @approval = id && SignInApproval.find_by(id: id, actor_id: actor.id, device_id: device&.id)
          end

          def approval_json
            return nil if approval.nil?

            {
              "code" => held["code"],
              "expiresIn" => approval.expires_in,
              "denied" => approval.denied? || nil,
              "expired" => (!approval.live? && !approval.denied?) || nil
            }.compact
          end

          def request_approval
            return warn!("missing-first-factor") unless login.first_factored?
            return if approval&.live? && !approval.answered? && approval.expires_in > SignInApproval.lifetime - 30.seconds

            opened, code = SignInApproval.open!(actor: actor, device: device)

            remove_instance_variable(:@approval) if defined?(@approval)
            login.store[HELD] = { "actor_id" => actor.id, "token_id" => opened.id, "code" => code }
          end

          def check
            return if approval.nil?
            return warn!("approval-denied") if approval.denied?
            return unless approval.approved? && approval.claim!

            login.store.delete(HELD)
            factored! :second_factor, expiry: OneTimePassword::EXPIRY
            remember! DeviceFactor::SECOND_FACTOR if remembering?
            login.noted! "mfa"
          end

          def remembering?
            device.present? && ActiveModel::Type::Boolean.new.cast(update(:remember))
          end
      end
    end
  end
end
