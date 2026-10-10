module Masks
  module Server
    module HelpRequests
      AGAIN_AFTER = 1.day

      class << self
        def request!(actor, journey:)
          return false if actor.recovery_requested_at&.after?(AGAIN_AFTER.ago)

          actor.update!(recovery_requested_at: Time.current)
          Event.record!(Event::RECOVERY_REQUESTED, actor: actor)

          return true unless ActorMailer.deliverable?

          helpers.where.not(email_verified_at: nil).where.not(id: actor.id).find_each do |manager|
            ActorMailer.recovery_requested(manager, actor, journey: journey).deliver_later
          end

          true
        end

        def reset!(actor, by:)
          actor.transaction do
            actor.passkeys.destroy_all
            actor.update!(
              otp_secret: nil, otp_enabled_at: nil, backup_code_digests: [], backup_codes_generated_at: nil,
              email_factor_at: nil, phone_factor_at: nil, recovery_requested_at: nil
            )
            DeviceFactor.forget!(actor: actor)
            actor.sign_out_everywhere!
          end

          Event.record!(Event::SECOND_FACTORS_RESET, actor: actor, by: by)
        end

        def dismiss!(actor, by:)
          actor.update!(recovery_requested_at: nil)

          Event.record!(Event::RECOVERY_DISMISSED, actor: actor, by: by)
        end

        private

          def helpers
            Actor.where(suspended_at: nil).merge(Actor.holding(Scopes::MANAGE).or(Actor.holding(Scopes::MANAGE_SUPPORT)))
          end
      end
    end
  end
end
