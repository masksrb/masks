module Masks
  module Server
    class Organization < ApplicationRecord
      include TenantScoped
      include Archivable

      OWNER = "owner".freeze
      MEMBER = "member".freeze
      BUILT_IN = [ OWNER, MEMBER ].freeze
      ROLE = /\A[a-z0-9][a-z0-9_-]{0,39}\z/

      has_many :memberships, dependent: :destroy
      has_many :actors, through: :memberships
      has_many :tokens, dependent: :destroy
      has_many :providers, dependent: :destroy

      belongs_to :sign_in_policy, optional: true

      validates :key, presence: true,
                      uniqueness: { scope: :tenant_id },
                      format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
      validates :name, presence: true
      validate :roles_are_named

      normalizes :roles, with: ->(held) { Array(held).map { |role| role.to_s.strip.downcase }.reject(&:empty?).uniq - BUILT_IN }

      def role_list
        BUILT_IN + roles
      end

      def role?(role)
        role_list.include?(role.to_s)
      end

      def membership_for(actor)
        return nil if actor.nil? || archived?

        memberships.find_by(actor: actor)
      end

      def claim_for(actor)
        membership = membership_for(actor)

        membership && { "id" => uuid, "key" => key, "name" => name, "role" => membership.role }
      end

      def archive!
        transaction do
          update!(archived_at: Time.current)
          tokens.live.find_each(&:revoke!)
        end
      end

      private

        def roles_are_named
          unnamed = roles.reject { |role| role.match?(ROLE) }

          errors.add(:roles, "must be lowercase letters, digits, dashes, and underscores: #{unnamed.join(', ')}") if unnamed.any?
        end
    end
  end
end
