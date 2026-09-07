class Event < ApplicationRecord
  include TenantScoped

  RETENTION = 180.days
  LIMIT = 50
  CEILING = 250
  AGENT_LIMIT = 500

  SESSION_STARTED = "session.started".freeze
  SESSION_ENDED = "session.ended".freeze
  SESSION_REVOKED = "session.revoked".freeze
  LOGOUT_UNDELIVERED = "logout.undelivered".freeze
  LOGIN_REFUSED = "login.refused".freeze
  LOGIN_THROTTLED = "login.throttled".freeze

  ACCOUNT_CREATED = "account.created".freeze
  INVITATION_SENT = "invitation.sent".freeze
  INVITATION_ACCEPTED = "invitation.accepted".freeze

  PASSWORD_CHANGED = "password.changed".freeze
  PASSWORD_RESET_REQUESTED = "password.reset_requested".freeze
  PASSWORD_RESET_COMPLETED = "password.reset_completed".freeze

  EMAIL_VERIFICATION_SENT = "email.verification_sent".freeze
  EMAIL_VERIFIED = "email.verified".freeze

  PASSKEY_ADDED = "passkey.added".freeze
  PASSKEY_REMOVED = "passkey.removed".freeze
  BACKUP_CODES_GENERATED = "backup_codes.generated".freeze
  BACKUP_CODE_SPENT = "backup_code.spent".freeze
  AUTHENTICATOR_DISABLED = "authenticator.disabled".freeze

  DEVICE_CODE_ISSUED = "device_code.issued".freeze
  DEVICE_CODE_APPROVED = "device_code.approved".freeze
  DEVICE_CODE_REFUSED = "device_code.refused".freeze

  DEVICE_TRUSTED = "device.trusted".freeze
  DEVICE_NAMED = "device.named".freeze
  DEVICE_FORGOTTEN = "device.forgotten".freeze
  DEVICE_BLOCKED = "device.blocked".freeze
  DEVICE_UNBLOCKED = "device.unblocked".freeze

  AVATAR_UPLOADED = "avatar.uploaded".freeze
  AVATAR_REMOVED = "avatar.removed".freeze

  CONSENT_GRANTED = "consent.granted".freeze
  CONSENT_REVOKED = "consent.revoked".freeze
  CONNECTION_LINKED = "connection.linked".freeze
  CONNECTION_UNLINKED = "connection.unlinked".freeze
  CONNECTION_SIGNED_IN = "connection.signed_in".freeze
  CONNECTION_REFUSED = "connection.refused".freeze

  ACTOR_CREATED = "actor.created".freeze
  ACTOR_PROVISIONED = "actor.provisioned".freeze
  ACTOR_UPDATED = "actor.updated".freeze
  ACTOR_DELETED = "actor.deleted".freeze
  ACTOR_SCOPES_CHANGED = "actor.scopes_changed".freeze
  ACTOR_SIGNED_OUT = "actor.signed_out".freeze

  CLIENT_REGISTERED = "client.registered".freeze
  CLIENT_APPROVED = "client.approved".freeze
  CLIENT_UPDATED = "client.updated".freeze
  CLIENT_ARCHIVED = "client.archived".freeze
  CLIENT_RESTORED = "client.restored".freeze
  CLIENT_SECRET_ROTATED = "client.secret_rotated".freeze

  TOKEN_REVOKED = "token.revoked".freeze
  REFRESH_REUSED = "refresh.reused".freeze

  SIGNING_KEY_STAGED = "signing_key.staged".freeze
  SIGNING_KEY_ROTATED = "signing_key.rotated".freeze
  SIGNING_KEY_ACTIVATED = "signing_key.activated".freeze
  SIGNING_KEY_DISCARDED = "signing_key.discarded".freeze

  NAMESPACE_RELEASED = "namespace.released".freeze
  PROVIDER_CREATED = "provider.created".freeze
  PROVIDER_UPDATED = "provider.updated".freeze
  PROVIDER_ARCHIVED = "provider.archived".freeze
  TENANT_UPDATED = "tenant.updated".freeze

  GRAVE = [
    LOGIN_REFUSED, LOGIN_THROTTLED, LOGOUT_UNDELIVERED, REFRESH_REUSED,
    DEVICE_BLOCKED, ACTOR_DELETED, AUTHENTICATOR_DISABLED, CONNECTION_REFUSED
  ].freeze

  ACTIONS = constants(false).filter_map do |name|
    value = const_get(name)
    value if value.is_a?(String) && value.include?(".")
  end.freeze

  belongs_to :actor, optional: true
  belongs_to :by, class_name: "Actor", optional: true
  belongs_to :client, optional: true
  belongs_to :device, optional: true

  validates :action, inclusion: { in: ACTIONS }

  include Paged

  class << self
    def record!(action, actor: nil, by: :subject, client: nil, device: :ambient,
                ip_address: :ambient, user_agent: :ambient, **details)
      create!(
        action: action,
        actor: actor,
        by: by == :subject ? actor : by,
        client: client,
        device: device == :ambient ? Current.device : device,
        ip_address: ip_address == :ambient ? Current.ip_address : ip_address,
        user_agent: clip(user_agent == :ambient ? Current.user_agent : user_agent),
        details: details.compact.deep_stringify_keys
      )
    end

    def clip(value)
      value.presence && value.to_s.truncate(AGENT_LIMIT)
    end

    def bounded(limit)
      [ limit.presence&.to_i || LIMIT, CEILING ].min
    end
  end

  def readonly?
    persisted?
  end
end
