module Masks
  module Server
    module IdleAccounts
      WARNING = 30.days

      class << self
        def sweep(tenant)
          return if tenant.idle_after.nil?

          after = tenant.idle_after.days

          candidates(after).find_each do |actor|
            next if actor.last_manager?

            settle(actor, tenant, after)
          end
        end

        def candidates(after)
          Actor.where(suspended_at: nil, external_id: nil)
               .where.not(activated_at: nil)
               .where("COALESCE(last_active_at, last_login_at, activated_at) < ?", (after - WARNING).ago)
        end

        def due(actor, after)
          [ actor.idle_since + after, (actor.idle_warned_at || Time.current) + WARNING ].max
        end

        private

          def settle(actor, tenant, after)
            return warn!(actor, tenant, after) if actor.idle_warned_at.nil?
            return if due(actor, after).future?

            tenant.idle_action == Tenant::IDLE_DELETE ? delete!(actor) : suspend!(actor)
          end

          def warn!(actor, tenant, after)
            actor.update_columns(idle_warned_at: Time.current)

            mailed = Notifications.mailable?(actor)

            Event.record!(Event::ACTOR_IDLE_WARNED, actor: actor, by: nil, mailed: mailed,
                          due: due(actor, after).iso8601, then: tenant.idle_action)

            return unless mailed

            ActorMailer.idle(
              actor,
              tenant_name: tenant.name,
              origin: Current.origin.presence || tenant.public_origin,
              due: due(actor, after),
              deleting: tenant.idle_action == Tenant::IDLE_DELETE
            ).deliver_later
          end

          def suspend!(actor)
            actor.suspend!

            Event.record!(Event::ACTOR_SUSPENDED, actor: actor, by: nil, reason: "idle",
                          idle_since: actor.idle_since&.iso8601)
          end

          def delete!(actor)
            held = { uuid: actor.uuid, identifier: actor.identifier, reason: "idle",
                     idle_since: actor.idle_since&.iso8601 }

            actor.erase!

            Event.record!(Event::ACTOR_DELETED, by: nil, **held)
          end
      end
    end
  end
end
