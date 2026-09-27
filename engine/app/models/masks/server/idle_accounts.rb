module Masks
  module Server
    module IdleAccounts
      WARNING = 30.days

      class << self
        def sweep(tenant)
          candidates(tenant).find_each do |actor|
            actor.with_lock do
              settle(actor, tenant) if idle?(actor, tenant) && !actor.last_manager?
            end
          end
        end

        private

          def threshold(tenant)
            (tenant.idle_after.days - WARNING).ago
          end

          def candidates(tenant)
            Actor.where(suspended_at: nil, external_id: nil)
                 .where.not(activated_at: nil)
                 .where("COALESCE(last_active_at, last_login_at, activated_at) < ?", threshold(tenant))
          end

          def idle?(actor, tenant)
            !actor.suspended? && actor.idle_since.present? && actor.idle_since < threshold(tenant)
          end

          def deadline(actor, tenant)
            [ actor.idle_since + tenant.idle_after.days, (actor.idle_warned_at || Time.current) + WARNING ].max
          end

          def settle(actor, tenant)
            return warn!(actor, tenant) if actor.idle_warned_at.nil?
            return if deadline(actor, tenant).future?

            tenant.idle_action == Tenant::IDLE_DELETE ? delete!(actor) : suspend!(actor)
          end

          def warn!(actor, tenant)
            actor.update_columns(idle_warned_at: Time.current)

            due = deadline(actor, tenant)
            mailed = Notifications.mailable?(actor)

            Event.record!(Event::ACTOR_IDLE_WARNED, actor: actor, by: nil, mailed: mailed,
                          due: due.iso8601, then: tenant.idle_action)

            return unless mailed

            ActorMailer.idle(
              actor,
              tenant_name: tenant.name,
              origin: Current.origin.presence || tenant.public_origin,
              due: due,
              action: tenant.idle_action
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

            actor.destroy!

            Event.record!(Event::ACTOR_DELETED, by: nil, **held)
          end
      end
    end
  end
end
