module Masks
  module Server
    module CodeFactors
      SPECS = {
        "email" => {
          channel: ConfirmationCode::EMAIL, sent_on: "email_factor", on: :email_factor_at,
          verified: :email_verified_at, held: :email_factor?, amr: "otp", icon: :email,
          enabled: Event::EMAIL_CODES_ENABLED, disabled: Event::EMAIL_CODES_DISABLED,
          deliverable: -> { ActorMailer.deliverable? },
          mask: ->(address) { name, domain = address.split("@", 2); "#{name.to_s[0]}•••@#{domain}" }
        },
        "sms" => {
          channel: ConfirmationCode::PHONE, sent_on: "phone_factor", on: :phone_factor_at,
          verified: :phone_verified_at, held: :phone_factor?, amr: "sms", icon: :device,
          enabled: Event::TEXT_CODES_ENABLED, disabled: Event::TEXT_CODES_DISABLED,
          deliverable: -> { Texting.deliverable? },
          mask: ->(address) { "•••• #{address.last(4)}" }
        }
      }.freeze

      FACTORS = SPECS.keys.freeze

      INDEPENDENT_OF_THE_INBOX = %w[pwd swk].freeze

      class << self
        def known?(factor)
          SPECS.key?(factor.to_s)
        end

        def spec(factor)
          SPECS.fetch(factor.to_s)
        end

        def held?(actor, factor)
          known?(factor) && actor.public_send(spec(factor)[:held])
        end

        def offered?(actor, factor, policy: SignInPolicy.for(tenant: Current.tenant))
          known?(factor) && (actor.manages? || policy.second_factor?(factor))
        end

        def confirmed?(actor, factor)
          address(actor, factor).present? && actor.public_send(spec(factor)[:verified]).present?
        end

        def deliverable?(factor)
          spec(factor)[:deliverable].call
        end

        def address(actor, factor)
          actor.public_send(spec(factor)[:channel])
        end

        def masked(actor, factor)
          spec(factor)[:mask].call(address(actor, factor).to_s)
        end

        def amr(factor)
          spec(factor)[:amr]
        end

        def icon(factor)
          spec(factor)[:icon]
        end

        def send!(actor, factor, journey:)
          held = spec(factor)
          to = address(actor, factor)
          token, code = ConfirmationCode.open!(actor: actor, channel: held[:sent_on], address: to)

          Confirmations.deliver(held[:channel], to, code, journey: journey)

          token
        end

        def sent(actor, factor, id)
          return nil if id.blank? || !known?(factor)

          token = ConfirmationCode.find_by(id: id, actor_id: actor.id)

          token if token&.live? && token.channel == spec(factor)[:sent_on] && token.address == address(actor, factor)
        end

        def enable!(actor, factor)
          held = spec(factor)
          now = Time.current

          actor.update!(held[:on] => now, held[:verified] => actor.public_send(held[:verified]) || now)

          Event.record!(held[:enabled], actor: actor)
        end

        def disable!(actor, factor, by: :subject)
          return false unless held?(actor, factor)

          actor.update!(spec(factor)[:on] => nil)

          Event.record!(spec(factor)[:disabled], actor: actor, by: by)
        end
      end
    end
  end
end
