module Masks
  module Server
    class Membership < ApplicationRecord
      class Unconfirmed < StandardError; end
      class Expired < StandardError; end

      include TenantScoped

      belongs_to :organization
      belongs_to :actor
      belongs_to :invited_by, class_name: "Actor", optional: true

      scope :accepted, -> { where(pending: false) }
      scope :invitations, -> { where(pending: true) }
      scope :lapsed, -> { invitations.where(invited_at: ...(lifetime * 2).ago) }
      scope :outstanding, -> { invitations.where(invited_at: lifetime.ago..) }
      scope :live, -> { accepted.joins(:organization).merge(Organization.active).includes(:organization).order("organizations.name") }

      before_create { self.invited_at ||= Time.current if pending? }

      def self.lifetime
        ::Rails.configuration.masks.organization_invitation_lifetime
      end

      validates :actor_id, uniqueness: { scope: :organization_id }
      validate :role_is_offered
      validate :an_owner_remains, on: :update

      before_destroy :keep_an_owner

      def owner?
        role == Organization::OWNER && !pending?
      end

      def expires_at
        invited_at + self.class.lifetime if pending?
      end

      def expired?
        expires_at.present? && expires_at <= Time.current
      end

      def addressed_to?(someone)
        invited_as.blank? || someone.email.to_s.casecmp?(invited_as)
      end

      def acceptable?
        return true if invited_as.blank?

        addressed_to?(actor) && actor.email_verified_at.present?
      end

      def claim
        { "id" => organization.uuid, "key" => organization.key, "name" => organization.name, "role" => role }
      end

      def accept!(vouched: false)
        return self unless pending?

        unless vouched
          raise Expired, "this invitation to #{organization.name} has expired" if expired?
          raise Unconfirmed, "confirm #{invited_as} before accepting" unless acceptable?
        end

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
          return if role_in_database != Organization::OWNER || pending_in_database || others_own?
          return ownerless! if destroyed_by_association

          errors.add(:base, "#{organization.name} needs an owner")
          throw :abort
        end

        def ownerless!
          return unless destroyed_by_association.active_record <= Actor

          Event.record!(Event::ORGANIZATION_OWNERLESS, actor: nil, by: nil, organization: organization)
        end

        def others_own?
          organization.memberships.accepted.where(role: Organization::OWNER).where.not(id: id).exists?
        end
    end
  end
end
