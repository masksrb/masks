module Masks
  module Server
    module AppPasswords
      FACTOR = "app_password".freeze
      THROTTLED = "throttled".freeze
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
          keys = { account_attempt: [ account_key(tenant, actor, identifier), "identifier" ], attempt: [ address_key(tenant, ip_address), nil ] }
          exceeded = keys.find { |limit, (by, named)| Throttle.exceeded?(limit, by, scope: SCOPE, named: named) }&.first

          if exceeded
            Throttle.hit!(exceeded, actor: actor, client: client, address: ip_address, identifier: identifier, via: via)
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
            [ tenant.id, actor&.id || identifier.to_s.strip.downcase ].join(":")
          end

          def address_key(tenant, ip_address)
            [ tenant.id, ip_address ].join(":")
          end

          def failed!(keys)
            keys.each { |limit, (by, named)| Throttle.count!(limit, by, scope: SCOPE, named: named) }
          end
      end
    end
  end
end
