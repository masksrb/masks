class Connection < ApplicationRecord
  include TenantScoped

  SKEW = 60.seconds
  DEFAULT_LIFETIME = 55.minutes

  encrypts :access_token
  encrypts :refresh_token

  belongs_to :provider
  belongs_to :actor

  has_many :delegations, dependent: :destroy
  has_many :live_delegations, -> { live }, class_name: "Delegation", inverse_of: :connection

  validates :subject, presence: true,
                      uniqueness: { scope: [ :tenant_id, :provider_id ] }

  scope :live, -> { where(revoked_at: nil) }

  class << self
    def record!(provider:, actor:, identity:)
      subject = identity["sub"].presence ||
        raise(ArgumentError, "#{provider.name} returned no #{provider.subject_claim} to identify the account by")

      connection = find_or_initialize_by(provider: provider, subject: subject.to_s)

      connection.actor = actor
      connection.label = identity.values_at("email", "preferred_username", "name").find(&:present?) || connection.label
      connection.connected_at = Time.current
      connection.revoked_at = nil
      connection.revoked_reason = nil
      connection.absorb_identity(identity)
      connection.save!

      connection
    end
  end

  def absorb_identity(identity)
    held = identity["email"].to_s.strip.downcase.presence

    return self if held.nil?

    self.email = held
    self.email_verified = identity["email_verified"] == true

    self
  end

  def signed_in!
    update!(signed_in_at: Time.current)

    self
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!(reason: "revoked", by: nil)
    transaction do
      update!(revoked_at: Time.current, revoked_reason: reason)
      forget_tokens!

      delegations.live.find_each { |delegation| delegation.revoke!(reason: reason, by: by) }
    end

    self
  end

  def hold!(tokens)
    raise Delegation::Refused, "#{provider.name} returned no access token" if tokens["access_token"].blank?

    store_tokens!(tokens, refresh_token: tokens["refresh_token"].presence,
                          delegated_scopes: Scopes.join(provider.delegated_scope_list))

    self
  end

  def delegable?
    return false if revoked? || !provider.delegating? || delegated_scopes.nil?
    return false unless Scopes.list(delegated_scopes) == provider.delegated_scope_list

    refresh_token.present? || !stale?
  end

  def stale?
    access_token.blank? || access_token_expires_at.nil? || access_token_expires_at <= SKEW.from_now
  end

  def release!
    outcome = with_lock do
      next :refused if revoked?
      next :fresh unless stale?
      next :refused if refresh_token.blank?

      refreshed = provider.refresh!(refresh_token)
      next :refused if refreshed["access_token"].blank?

      store_tokens!(refreshed, refresh_token: refreshed["refresh_token"].presence || refresh_token)
      :fresh
    rescue Provider::Refused
      :refused
    rescue Provider::Unreachable
      :unavailable
    end

    case outcome
    when :fresh then { "access_token" => access_token, "expires_at" => access_token_expires_at, "scope" => delegated_scopes }
    when :unavailable then raise Delegation::Unavailable, "#{provider.name} did not answer a refresh"
    else
      forget_tokens! unless revoked?
      raise Delegation::Refused, "#{provider.name} no longer honours this connection; connect it again"
    end
  end

  def forget_tokens!
    update!(access_token: nil, refresh_token: nil, access_token_expires_at: nil, delegated_scopes: nil)

    self
  end

  private

    def store_tokens!(tokens, **attributes)
      update!(access_token: tokens["access_token"], access_token_expires_at: expiry_from(tokens),
              tokens_refreshed_at: Time.current, **attributes)
    end

    def expiry_from(tokens)
      seconds = tokens["expires_in"].to_i

      seconds.positive? ? seconds.seconds.from_now : DEFAULT_LIFETIME.from_now
    end
end
