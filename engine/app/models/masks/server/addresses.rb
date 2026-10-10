module Masks
  module Server
    module Addresses
      HELD = "address_changes".freeze

      CHANNELS = {
        ConfirmationCode::EMAIL => { verified: :email_verified_at, event: Event::EMAIL_CHANGED },
        ConfirmationCode::PHONE => { verified: :phone_verified_at, event: Event::PHONE_CHANGED }
      }.freeze

      class << self
        def deliverable?(channel)
          channel == ConfirmationCode::EMAIL ? ActorMailer.deliverable? : Texting.deliverable?
        end

        def normalize(channel, value)
          return Adapters::Sms.number(value) if channel == ConfirmationCode::PHONE

          email = value.to_s.strip
          email if email.match?(URI::MailTo::EMAIL_REGEXP)
        end

        def request!(actor, channel, address, journey:)
          token, code = ConfirmationCode.open!(actor: actor, channel: channel, address: address)

          Confirmations.deliver(channel, address, code, journey: journey)

          token
        end

        def pending(session, actor)
          held = session[HELD]
          return {} unless held.is_a?(Hash) && held["actor_id"] == actor.id

          CHANNELS.keys.filter_map do |channel|
            token = held[channel] && ConfirmationCode.find_by(id: held[channel], actor_id: actor.id)

            [ channel, token ] if token&.live? && token.channel == channel
          end.to_h
        end

        def hold(session, actor, channel, token)
          held = session[HELD].is_a?(Hash) && session[HELD]["actor_id"] == actor.id ? session[HELD] : {}

          session[HELD] = held.merge("actor_id" => actor.id, channel => token&.id).compact
        end

        def confirm!(actor, token, code)
          return :invalid unless token.verify(code)

          channel = token.channel
          spec = CHANNELS.fetch(channel)
          previous = actor.public_send(channel)
          told = actor.public_send(spec[:verified]).present? ? previous : nil

          return :taken unless actor.update(channel => token.address, spec[:verified] => Time.current)

          Event.record!(spec[:event], actor: actor, previous: told)

          :changed
        end
      end
    end
  end
end
