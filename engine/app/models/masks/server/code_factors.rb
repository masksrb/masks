module Masks
  module Server
    module CodeFactors
      FACTORS = %w[email sms].freeze

      CHANNELS = { "email" => ConfirmationCode::EMAIL, "sms" => ConfirmationCode::PHONE }.freeze
      SENT_ON = { "email" => "email_factor", "sms" => "phone_factor" }.freeze
      ENABLED = { "email" => Event::EMAIL_CODES_ENABLED, "sms" => Event::TEXT_CODES_ENABLED }.freeze
      DISABLED = { "email" => Event::EMAIL_CODES_DISABLED, "sms" => Event::TEXT_CODES_DISABLED }.freeze

      INDEPENDENT_OF_THE_INBOX = %w[pwd swk].freeze

      class << self
        def known?(factor)
          FACTORS.include?(factor.to_s)
        end

        def held?(actor, factor)
          known?(factor) && actor.code_factor?(CHANNELS.fetch(factor.to_s))
        end

        def offered?(actor, factor, policy: SignInPolicy.for(tenant: Current.tenant))
          known?(factor) && (actor.manages? || policy.second_factor?(factor))
        end

        def confirmed?(actor, factor)
          verified = factor.to_s == "email" ? actor.email_verified_at : actor.phone_verified_at

          address(actor, factor).present? && verified.present?
        end

        def deliverable?(factor)
          factor.to_s == "email" ? ActorMailer.deliverable? : Texting.deliverable?
        end

        def address(actor, factor)
          actor.public_send(CHANNELS.fetch(factor.to_s))
        end

        def masked(actor, factor)
          held = address(actor, factor).to_s

          if factor.to_s == "email"
            name, domain = held.split("@", 2)
            "#{name.to_s[0]}•••@#{domain}"
          else
            "•••• #{held.last(4)}"
          end
        end

        def send!(actor, factor)
          to = address(actor, factor)
          token, code = ConfirmationCode.open!(actor: actor, channel: SENT_ON.fetch(factor.to_s), address: to)
          tenant_name = Current.tenant&.name

          if factor.to_s == "email"
            ActorMailer.confirmation_code(to, code, tenant_name: tenant_name).deliver_later
          else
            Texting.deliver_later(to: to, body: I18n.t("texts.code", code: code, tenant: tenant_name))
          end

          token
        end

        def sent(actor, factor, id)
          return nil if id.blank? || !known?(factor)

          token = ConfirmationCode.find_by(id: id, actor_id: actor.id)

          token if token&.live? && token.channel == SENT_ON.fetch(factor.to_s) && token.address == address(actor, factor)
        end

        def enable!(actor, factor)
          actor.adopt_code_factor!(CHANNELS.fetch(factor.to_s))

          Event.record!(ENABLED.fetch(factor.to_s), actor: actor)
        end

        def disable!(actor, factor, by: :subject)
          return false unless held?(actor, factor)

          actor.drop_code_factor!(CHANNELS.fetch(factor.to_s))

          Event.record!(DISABLED.fetch(factor.to_s), actor: actor, by: by)
        end

        def amr(factor)
          factor.to_s == "sms" ? "sms" : "otp"
        end
      end
    end
  end
end
