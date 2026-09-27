module Masks
  module Server
    class Membership < ApplicationRecord
      include TenantScoped

      belongs_to :organization
      belongs_to :actor
      belongs_to :invited_by, class_name: "Actor", optional: true

      scope :accepted, -> { where(pending: false) }

      validates :actor_id, uniqueness: { scope: :organization_id }
      validate :role_is_offered
      validate :an_owner_remains, on: :update

      before_destroy :keep_an_owner

      def owner?
        role == Organization::OWNER && !pending?
      end

      def accept!
        return self unless pending?

        update!(pending: false)
        Event.record!(Event::MEMBERSHIP_ACCEPTED, actor: actor, organization: organization, role: role)

        self
      end

      private

        def role_is_offered
          errors.add(:role, "is not one #{organization&.name} offers") unless organization&.role?(role)
        end

        def an_owner_remains
          return unless role_changed? && role_was == Organization::OWNER
          return if pending_in_database || others_own?

          errors.add(:role, "cannot change, because #{organization.name} needs an owner")
        end

        def keep_an_owner
          return if role_in_database != Organization::OWNER || pending_in_database || destroyed_by_association || others_own?

          errors.add(:base, "#{organization.name} needs an owner")
          throw :abort
        end

        def others_own?
          organization.memberships.accepted.where(role: Organization::OWNER).where.not(id: id).exists?
        end
    end
  end
end
