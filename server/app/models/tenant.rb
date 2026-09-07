class Tenant < ApplicationRecord
  class TenancyConflict < StandardError
    def initialize(message = "MASKS_TENANT and MASKS_TENANTS are both set; declare one or the other")
      super
    end
  end

  class Exposed < StandardError
    def initialize(role)
      super(
        "this server connects to Postgres as #{role || 'a role it cannot read back'}, which sees " \
        "through row-level security. Every tenant_isolation policy on the database is decorative " \
        "while it does, and the only thing left between one tenant and another's actors, tokens " \
        "and signing keys is a default scope in Ruby. Connect as a role holding neither SUPERUSER " \
        "nor BYPASSRLS."
      )
    end
  end

  encrypts :pairwise_salt

  has_many :signing_keys, dependent: :destroy
  has_many :actors, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :tokens, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :consents, dependent: :destroy
  has_many :events, dependent: :delete_all

  validates :subdomain, presence: true, uniqueness: true,
                        format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true

  scope :active, -> { where(archived_at: nil) }

  after_create_commit :ensure_signing_key!

  def public_origin
    template = Rails.configuration.masks.public_origin_template

    template && format(template, subdomain: subdomain).chomp("/")
  end

  def dynamic_client_ceiling
    declared = dynamic_client_scopes.presence ||
      Rails.configuration.masks.dynamic_client_scopes

    declared && Scopes.list(declared)
  end

  class << self
    def pinned
      Rails.configuration.masks.tenant
    end

    def resolve(host)
      return active.find_by(subdomain: pinned) if pinned

      active.find_by(subdomain: host.to_s.split(".").first)
    end

    def declared
      return Rails.configuration.masks.tenants unless pinned
      raise TenancyConflict if Rails.configuration.masks.tenants.any?

      [ pinned ]
    end

    def declare!
      declared.map do |subdomain|
        active.find_by(subdomain: subdomain) || create!(subdomain: subdomain, name: subdomain.titleize)
      end
    end

    def claim(host)
      return nil if declared.any?
      return nil if exists?

      subdomain = host.to_s.split(".").first

      create!(subdomain: subdomain, name: subdomain.titleize)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil
    end

    def isolated!
      return true if @isolated

      held = role_privileges

      raise Exposed, held&.fetch("rolname", nil) unless held && held["bypasses"] == false

      @isolated = true
    end

    def role_privileges
      connection.select_one(<<~SQL)
        SELECT rolname, rolsuper OR rolbypassrls AS bypasses
        FROM pg_roles WHERE rolname = current_user
      SQL
    end

    def switch(tenant)
      raise ArgumentError, "no tenant" if tenant.nil?

      isolated!

      return yield tenant if Current.tenant&.id == tenant.id

      held = Current.tenant

      enter(tenant)

      begin
        yield tenant
      ensure
        enter(held)
      end
    end

    def clear!
      enter(nil)
    end

    private

      def enter(tenant)
        Current.tenant = tenant

        connection.exec_query(
          "SELECT set_config($1, $2, false)", "tenant",
          [ TenantIsolation::SETTING, tenant&.id.to_s ]
        )

        connection.clear_query_cache
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
        nil
      end
  end

  def signing_key
    Tenant.switch(self) { signing_keys.active.first } || ensure_signing_key!
  end

  def pairwise_salt!
    return pairwise_salt if pairwise_salt.present?

    with_lock { update!(pairwise_salt: SecureRandom.hex(32)) if pairwise_salt.blank? }

    pairwise_salt
  end

  def ensure_signing_key!
    Tenant.switch(self) do
      signing_keys.active.first || SigningKey.generate!(tenant: self)
    end
  end

  def to_identity
    { "uuid" => uuid, "subdomain" => subdomain, "name" => name }
  end
end
