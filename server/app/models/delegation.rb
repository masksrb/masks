class Delegation < ApplicationRecord
  include TenantScoped

  class Refused < StandardError; end
  class Unavailable < StandardError; end

  belongs_to :client
  belongs_to :actor
  belongs_to :connection

  has_one :provider, through: :connection

  scope :live, -> { where(revoked_at: nil) }

  class << self
    def grant!(client:, actor:, connection:)
      held = covering(client: client, actor: actor, connection: connection)
      return held if held

      delegation = create!(
        client: client, actor: actor, connection: connection,
        scopes: Scopes.join(connection.provider.delegated_scope_list), consented_at: Time.current
      )

      Event.record!(
        Event::DELEGATION_GRANTED,
        actor: actor, by: nil, client: client, provider: connection.provider.key, connection: connection.uuid
      )

      delegation
    end

    def covering(client:, actor:, connection:)
      live.find_by(client: client, actor: actor, connection: connection)
    end
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!(reason: "revoked", by: nil)
    return self if revoked?

    transaction do
      update!(revoked_at: Time.current, revoked_reason: reason)

      withdraw_scope! unless siblings.exists?

      Event.record!(
        Event::DELEGATION_REVOKED,
        actor: actor, by: by, client: client, provider: connection.provider.key, connection: connection.uuid, reason: reason
      )
    end

    self
  end

  def siblings
    Delegation.live.where(client: client, actor: actor).where.not(id: id)
      .joins(:connection).where(connections: { provider_id: connection.provider_id, revoked_at: nil })
  end

  def release!
    upstream = connection.release!

    update_column(:released_at, Time.current)

    Event.record!(
      Event::DELEGATION_RELEASED,
      actor: actor, by: nil, client: client, provider: connection.provider.key, connection: connection.uuid
    )

    upstream
  end

  private

    def withdraw_scope!
      scope = connection.provider.delegation_scope

      RefreshToken.live.where(client: client, actor: actor).find_each do |token|
        token.revoke! if token.scope_list.include?(scope)
      end

      Consent.live.where(client: client, actor: actor).find_each do |consent|
        consent.update!(scopes: Scopes.join(Scopes.list(consent.scopes) - [ scope ]))
      end
    end
end
