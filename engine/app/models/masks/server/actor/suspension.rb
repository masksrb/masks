module Masks
  module Server
    class Actor
      module Suspension
        extend ActiveSupport::Concern

        ACTIVITY_GRAIN = 1.day

        IDLE = "idle".freeze
        MANAGER = "manager".freeze
        SCIM = "scim".freeze
        SUSPENSIONS = [ IDLE, MANAGER, SCIM ].freeze

        included do
          before_destroy :sign_out_everywhere!, prepend: true

          validates :suspension_reason, inclusion: { in: SUSPENSIONS }, allow_nil: true
        end

        def suspended?
          suspended_at.present?
        end

        def suspend!(reason:)
          return self if suspended?

          transaction do
            update!(suspended_at: Time.current, suspension_reason: reason, idle_warned_at: nil)
            sign_out_everywhere!
            Token.where(actor_id: id).live.update_all(consumed_at: Time.current, updated_at: Time.current)
          end

          self
        end

        def restore!
          return self unless suspended?

          update!(suspended_at: nil, suspension_reason: nil, idle_warned_at: nil, last_active_at: Time.current)
          self
        end

        def directed?
          Actor.directed.exists?(id)
        end

        def last_manager?
          persisted? && owns? && !Actor.holding(Scopes::MANAGE).where(suspended_at: nil).where.not(id: id).exists?
        end

        def active!
          return if last_active_at && last_active_at > ACTIVITY_GRAIN.ago

          update_columns(last_active_at: Time.current, idle_warned_at: nil)
        end

        def idle_since
          last_active_at || last_login_at || activated_at
        end

        def sign_out_everywhere!(keeping: nil)
          held = sessions.live
          held = held.where.not(id: keeping.id) if keeping

          held.find_each(&:revoke!)
          RefreshToken.where(actor_id: id).live.find_each(&:revoke!)

          issued = AccessToken.where(actor_id: id).live
          issued = issued.where.not(session_id: keeping.id) if keeping
          issued.update_all(consumed_at: Time.current, updated_at: Time.current)

          DeviceFactor.forget!(actor: self)
        end
      end
    end
  end
end
