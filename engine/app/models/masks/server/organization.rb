module Masks
  module Server
    class Organization < ApplicationRecord
      include TenantScoped
      include Archivable

      OWNER = "owner".freeze
      MEMBER = "member".freeze
      BUILT_IN = [ OWNER, MEMBER ].freeze
      ROLE = /\A[a-z0-9][a-z0-9_-]{0,39}\z/
      CLAIM = "org".freeze

      has_many :memberships, dependent: :destroy
      has_many :actors, -> { merge(Membership.accepted) }, through: :memberships
      has_many :tokens, dependent: :destroy
      has_many :providers, dependent: :destroy

      belongs_to :sign_in_policy, optional: true

      validates :key, presence: true,
                      uniqueness: { scope: :tenant_id },
                      format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
      validates :name, presence: true
      validate :roles_are_named
      validate :roles_still_held, on: :update, if: :roles_changed?

      normalizes :roles, with: ->(held) { Array(held).map { |role| role.to_s.strip.downcase }.reject(&:empty?).uniq - BUILT_IN }

      def role_list
        BUILT_IN + roles
      end

      def role?(role)
        role_list.include?(role.to_s)
      end

      def membership_for(actor)
        return nil if actor.nil? || archived?

        memberships.accepted.find_by(actor: actor)
      end

      def claim_for(actor)
        membership_for(actor)&.claim
      end

      def archive!(by: nil)
        transaction do
          update!(archived_at: Time.current)
          held = tokens.live.where.not(actor_id: nil).distinct.pluck(:actor_id)
          tokens.live.find_each(&:revoke!)

          Actor.where(id: held).find_each do |actor|
            Event.record!(Event::MEMBERSHIP_SUSPENDED, actor: actor, by: by, organization: self)
          end
        end
      end

      private

        def roles_are_named
          unnamed = roles.reject { |role| role.match?(ROLE) }

          errors.add(:roles, "must be lowercase letters, digits, dashes, and underscores: #{unnamed.join(', ')}") if unnamed.any?
        end

        def roles_still_held
          held = memberships.where.not(role: role_list).distinct.pluck(:role)

          errors.add(:base, :held, message: "members still hold #{held.join(', ')}") if held.any?
        end
    end
  end
end
