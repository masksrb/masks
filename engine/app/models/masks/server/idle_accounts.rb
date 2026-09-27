module Masks
  module Server
    module IdleAccounts
      WARNING = 30.days
      SUSPEND = "suspend".freeze
      DELETE = "delete".freeze

      class << self
        def sweep(tenant)
          candidates(tenant).find_each do |actor|
            actor.with_lock do
              stage = stage(actor, tenant)

              settle(actor, tenant, stage) if stage && !actor.last_manager?
            end
          end
        end

        private

          def after(tenant, stage)
            (stage == SUSPEND ? tenant.suspend_after : tenant.delete_after).days
          end

          def candidates(tenant)
            soonest = [ tenant.suspend_after, tenant.delete_after ].compact.min.days

            Actor.where(external_id: nil)
                 .where("suspended_at IS NULL OR idle_suspended")
                 .where.not(activated_at: nil)
                 .where("COALESCE(last_active_at, last_login_at, activated_at) < ?", (soonest - WARNING).ago)
          end

          def stage(actor, tenant)
            upcoming =
              if !actor.suspended? && tenant.suspend_after then SUSPEND
              elsif tenant.delete_after && (!actor.suspended? || actor.idle_suspended?) then DELETE
              end

            upcoming if upcoming && actor.idle_since && actor.idle_since < (after(tenant, upcoming) - WARNING).ago
          end

          def deadline(actor, tenant, stage)
            [ actor.idle_since + after(tenant, stage), actor.idle_warned_at + WARNING ].max
          end

          def settle(actor, tenant, stage)
            return warn!(actor, tenant, stage) unless actor.idle_warning == stage && actor.idle_warned_at
            return if deadline(actor, tenant, stage).future?

            stage == SUSPEND ? suspend!(actor) : delete!(actor)
          end

          def warn!(actor, tenant, stage)
            actor.update_columns(idle_warned_at: Time.current, idle_warning: stage)

            due = deadline(actor, tenant, stage)
            mailed = Notifications.mailable?(actor)

            Event.record!(Event::ACTOR_IDLE_WARNED, actor: actor, by: nil, mailed: mailed,
                          due: due.iso8601, then: stage)

            return unless mailed

            ActorMailer.idle(
              actor,
              tenant_name: tenant.name,
              origin: Current.origin.presence || tenant.public_origin,
              due: due,
              action: stage
            ).deliver_later
          end

          def suspend!(actor)
            actor.suspend!(idle: true)

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
