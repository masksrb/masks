module Masks
  module Server
    module IdleAccounts
      WARNING = 30.days
      SUSPEND = "suspend".freeze
      DELETE = "delete".freeze
      DELETE_SUSPENDED = "delete_suspended".freeze

      class << self
        def sweep(tenant)
          candidates(tenant).find_each do |actor|
            next unless stage(actor, tenant)

            actor.with_lock do
              stage = stage(actor, tenant)

              settle(actor, tenant, stage) if stage
            end
          end
        end

        private

          def days(tenant, stage)
            stage == SUSPEND ? tenant.suspend_after : tenant.delete_after
          end

          def warn_from(days)
            (days.days - WARNING).ago
          end

          def candidates(tenant)
            unsuspended = Actor.where(suspended_at: nil)
            eligible = tenant.delete_after ? unsuspended.or(Actor.where(suspension_reason: Actor::IDLE)) : unsuspended
            soonest = [ tenant.suspend_after, tenant.delete_after ].compact.min

            eligible.where(external_id: nil)
                    .where.not(activated_at: nil)
                    .where("COALESCE(last_active_at, last_login_at, activated_at) < ?", warn_from(soonest))
          end

          def stage(actor, tenant)
            return if actor.suspended? && actor.suspension_reason != Actor::IDLE

            upcoming = actor.suspended? || tenant.suspend_after.nil? ? DELETE : SUSPEND
            after = days(tenant, upcoming)

            upcoming if after && actor.idle_since < warn_from(after)
          end

          def deadline(actor, tenant, stage)
            [ actor.idle_since + days(tenant, stage).days, actor.idle_warned_at + WARNING ].max
          end

          def settle(actor, tenant, stage)
            return if actor.idle_warned_at && deadline(actor, tenant, stage).future?
            return if actor.last_manager?
            return warn!(actor, tenant, stage) if actor.idle_warned_at.nil?

            stage == SUSPEND ? suspend!(actor) : delete!(actor)
          end

          def warn!(actor, tenant, stage)
            actor.update_columns(idle_warned_at: Time.current)

            due = deadline(actor, tenant, stage)
            notice = actor.suspended? ? DELETE_SUSPENDED : stage
            mailed = Notifications.mailable?(actor)

            Event.record!(Event::ACTOR_IDLE_WARNED, actor: actor, by: nil, mailed: mailed,
                          due: due.iso8601, then: notice)

            return unless mailed

            ActorMailer.idle(
              actor,
              tenant_name: tenant.name,
              origin: Current.origin.presence || tenant.public_origin,
              due: due,
              notice: notice
            ).deliver_later
          end

          def suspend!(actor)
            actor.suspend!(reason: Actor::IDLE)

            Event.record!(Event::ACTOR_SUSPENDED, actor: actor, by: nil, reason: Actor::IDLE,
                          idle_since: actor.idle_since&.iso8601)
          end

          def delete!(actor)
            held = { uuid: actor.uuid, identifier: actor.identifier, reason: Actor::IDLE,
                     idle_since: actor.idle_since&.iso8601 }

            actor.destroy!

            Event.record!(Event::ACTOR_DELETED, by: nil, **held)
          end
      end
    end
  end
end
