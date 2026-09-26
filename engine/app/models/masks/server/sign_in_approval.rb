module Masks
  module Server
    class SignInApproval < Token
      VERDICTS = %w[approved denied].freeze

      class << self
        def lifetime
          5.minutes
        end

        def open!(actor:, device:)
          live.where(actor_id: actor.id, device_id: device&.id).update_all(consumed_at: Time.current)

          code, secret = ConfirmationCode.generate

          [ mint!(actor: actor, device: device, payload: secret), code ]
        end

        def matching(actor:, code:, from:)
          waiting.where(actor_id: actor.id).where.not(device_id: from&.id).order(:created_at)
                 .find { |approval| ConfirmationCode.matches?(approval.payload, code) }
        end

        def waiting
          live.where("payload->>'approved_at' IS NULL AND payload->>'denied_at' IS NULL")
        end

        def approvers?(actor:, except:)
          DeviceFactor.live.where(actor: actor, factor: DeviceFactor::SECOND_FACTOR)
                      .where.not(device_id: except&.id).exists?
        end
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

      def resendable?
        created_at <= ConfirmationCode::RESEND_AFTER.ago
      end

      def answer!(verdict, by:)
        raise ArgumentError, "unknown verdict #{verdict}" unless VERDICTS.include?(verdict)

        with_lock do
          next false unless live? && !answered?

          update!(payload: payload.merge("#{verdict}_at" => Time.current.iso8601, "#{verdict}_by" => by.id),
                  consumed_at: verdict == "denied" ? Time.current : nil)
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
