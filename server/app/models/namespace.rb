class Namespace < ApplicationRecord
  include TenantScoped

  class Taken < StandardError; end

  belongs_to :client, optional: true

  validates :name, presence: true, uniqueness: { scope: :tenant_id }
  validates :resource, presence: true
  validate :name_is_a_prefix
  validate :name_is_not_reserved

  class << self
    def prefixes(scopes)
      Scopes.list(scopes).select { |scope| Scopes.prefix?(scope) }
    end

    def named(scopes)
      where(name: prefixes(scopes))
    end

    def held_by(resource)
      where(resource: resource.to_s)
    end

    def taken(handshake)
      named(handshake.scopes).where.not(resource: handshake.resource.to_s)
    end

    def refusal(handshake)
      held = taken(handshake)
      return nil if held.empty?

      held.map { |row| "#{row.name} is claimed by #{row.resource}" }.join(", ")
    end

    def claim!(handshake, client:, actor: nil)
      names = prefixes(handshake.scopes)
      return [] if names.empty?

      transaction do
        raise Taken, refusal(handshake) if taken(handshake).exists?

        claimed = names.map do |name|
          row = find_or_initialize_by(name: name)

          row.assign_attributes(
            client: client,
            resource: handshake.resource,
            claimed_at: Time.current
          )

          row.save!
          row
        end

        actor&.grant!(names)

        claimed
      end
    end
  end

  def releasable?
    client.nil? || client.archived_at.present?
  end

  def release!
    destroy!
  end

  private

    def name_is_a_prefix
      return if Scopes.prefix?(name)

      errors.add(:name, "must end in a colon")
    end

    def name_is_not_reserved
      return unless name.to_s == Scopes::NAMESPACE

      errors.add(:name, "belongs to this issuer")
    end
end
