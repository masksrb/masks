module Masks
  module Server
    class SignInApproval < Token
      DIGITS = 6

      class << self
        def lifetime
          5.minutes
        end

        def open!(actor:, device:)
          live.where(actor_id: actor.id, device_id: device&.id).update_all(consumed_at: Time.current)

          code = SecureRandom.random_number(10**DIGITS).to_s.rjust(DIGITS, "0")
          salt = SecureRandom.hex(16)

          token = mint!(actor: actor, device: device,
                        payload: { "salt" => salt, "digest" => ConfirmationCode.digest(salt, code) })

          [ token, code ]
        end

        def matching(actor:, code:, from:)
          entered = code.to_s.delete("^0-9")
          return nil unless entered.length == DIGITS

          live.where(actor_id: actor.id).where.not(device_id: from&.id).order(:created_at).to_a
              .reject(&:answered?).find { |approval| approval.matches?(entered) }
        end

        def trusted?(actor:, device:)
          DeviceFactor.satisfied?(device: device, actor: actor)
        end

        def approvers?(actor:, except:)
          DeviceFactor.live.where(actor: actor, factor: DeviceFactor::SECOND_FACTOR)
                      .where.not(device_id: except&.id).exists?
        end
      end

      def matches?(code)
        ActiveSupport::SecurityUtils.secure_compare(ConfirmationCode.digest(held("salt"), code.to_s), held("digest"))
      end

      def approved?
        held("approved_at").present?
      end

      def denied?
        held("denied_at").present?
      end

      def answered?
        approved? || denied?
      end

      def approve!(by:)
        with_lock do
          next false unless live? && !answered?

          update!(payload: payload.merge("approved_at" => Time.current.iso8601, "approved_by" => by.id))
        end
      end

      def deny!(by:)
        with_lock do
          next false unless live? && !answered?

          update!(payload: payload.merge("denied_at" => Time.current.iso8601, "denied_by" => by.id),
                  consumed_at: Time.current)
        end
      end

      def claim!
        with_lock do
          next false unless live? && approved?

          update!(consumed_at: Time.current)
        end
      end
    end
  end
end
