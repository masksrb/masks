module Masks
  module Server
    module AppPasswords
      FACTOR = "app_password".freeze
      THROTTLED = "throttled".freeze
      WINDOW = 3.minutes
      SCOPE = "masks/server/logins".freeze

      Outcome = Data.define(:actor, :refusal) do
        def throttled?
          refusal == THROTTLED
        end

        def wrong?
          refusal == FACTOR
        end
      end

      class << self
        def authenticate(client:, identifier:, secret:, via:, ip_address: Current.ip_address, tenant: Current.tenant)
          return refused(nil, identifier, "factor-not-offered", via, client) unless client&.app_passwords? && !client.archived?

          actor = Actor.locate(identifier)
          keys = [ account_key(tenant, actor, identifier), address_key(tenant, ip_address) ]

          if throttled?(keys)
            Event.record!(Event::LOGIN_THROTTLED, actor: actor, by: nil, client: client, identifier: identifier, via: via)
            return Outcome.new(actor: nil, refusal: THROTTLED)
          end

          held = AppPassword.check(actor: actor, client: client, secret: secret)

          if held.nil?
            failed!(keys)
            return refused(actor, identifier, FACTOR, via, client)
          end

          reason = obstacle(client, actor)
          return refused(actor, identifier, reason, via, client) if reason

          actor.active!
          held.used!

          Outcome.new(actor: actor, refusal: nil)
        end

        private

          def obstacle(client, actor)
            return "suspended" if actor.suspended?
            return "pending_approval" if actor.pending_approval_at.present?

            "not_admitted" unless client.admits?(actor)
          end

          def refused(actor, identifier, factor, via, client)
            Event.record!(Event::LOGIN_REFUSED, actor: actor, by: nil, client: client, factor: factor, identifier: identifier, via: via)

            Outcome.new(actor: nil, refusal: factor)
          end

          def account_key(tenant, actor, identifier)
            [ "rate-limit", SCOPE, "identifier", tenant.id, actor&.id || identifier.to_s.strip.downcase ].join(":")
          end

          def address_key(tenant, ip_address)
            [ "rate-limit", SCOPE, tenant.id, ip_address ].join(":")
          end

          def throttled?(keys)
            limits = [ ::Rails.configuration.masks.account_attempt_limit, ::Rails.configuration.masks.attempt_limit ]

            keys.zip(limits).any? { |key, limit| ::Rails.cache.read(key).to_i >= limit }
          end

          def failed!(keys)
            keys.each { |key| ::Rails.cache.increment(key, 1, expires_in: WINDOW) }
          end
      end
    end
  end
end
