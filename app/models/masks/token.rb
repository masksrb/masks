module Masks
  class Token < ApplicationRecord
    self.table_name = "masks_tokens"

    class << self
      def copy!(token)
        copy(token).tap { |t| t.save! }
      end

      def copy(token)
        new(
          token: token,
          actor: token.actor,
          device: token.device,
          client: token.client,
          redirect_uri: token.redirect_uri,
          scopes: token.scopes,
          nonce: token.nonce,
        )
      end
    end

    include Cleanable
    include SettingsColumn
    include ScopesColumn

    scope :usable,
          -> { where("revoked_at IS NULL AND expires_at >= ?", Time.now.utc) }

    belongs_to :client, class_name: "Masks::Client"
    belongs_to :device, class_name: "Masks::Device", optional: true
    belongs_to :actor, class_name: "Masks::Actor", optional: true
    belongs_to :token, class_name: "Masks::Token", optional: true

    after_initialize :generate_token
    before_validation :generate_defaults

    validates :type, :secret, presence: true
    validates :expires_at, presence: true, if: :client
    validates :secret, uniqueness: true
    validates :key, uniqueness: true
    validates :name, length: { maximum: 255 }

    attribute :expiry
    attribute :deobfuscate

    def session_key
      secret
    end

    def session_lifetime
      expires_at
    end

    def expired?
      return true unless expires_at

      expires_at < Time.now.utc
    end

    def usable?
      !revoked_at && !expired?
    end

    def valid_redirect_uri?(value)
      ActiveSupport::SecurityUtils.secure_compare(value, self.redirect_uri)
    end

    def obfuscated_secret
      if deobfuscate
        secret
      else
        StringObfuscator.obfuscate(secret, percent: 75, from: :right)
      end
    end

    def public_id
      key
    end

    def public_type
      expiry_name.humanize
    end

    def revoke!
      revoked(true)
      save!
    end

    def revoked(value)
      if value
        self.revoked_at = Time.current
      else
        self.revoked_at = nil
      end
    end

    def bearer_token?
      false
    end

    private

    def generate_token
      self.key ||= SecureRandom.base58(64)
      self.secret ||= SecureRandom.base58(64)
    end

    def generate_defaults
      self.expires_at ||=
        if expiry
          client&.expires_at(custom: expiry)
        else
          client&.expires_at(expiry_name)
        end
    end

    def expiry_name
      self.class.name.split("::").last.underscore
    end
  end
end
