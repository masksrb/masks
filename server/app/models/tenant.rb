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

  NICKNAME = "nickname".freeze
  EMAIL = "email".freeze
  EITHER = "either".freeze
  NAMES = [ NICKNAME, EMAIL, EITHER ].freeze

  AUTHENTICATIONS = %w[plain login cram_md5].freeze
  SMTP_PORT = 587
  SMTP_TIMEOUT = 10

  REGISTRATION_OFF = "off".freeze
  REGISTRATION_ANYTHING = "anything".freeze
  REGISTRATION_BOUNDED = "bounded".freeze
  REGISTRATIONS = [ REGISTRATION_OFF, REGISTRATION_ANYTHING, REGISTRATION_BOUNDED ].freeze

  encrypts :smtp_password

  validates :named_by, inclusion: { in: NAMES }, allow_nil: true
  validates :dynamic_registration, inclusion: { in: REGISTRATIONS }, allow_nil: true
  validates :smtp_authentication, inclusion: { in: AUTHENTICATIONS }, allow_blank: true
  validates :smtp_port, numericality: { only_integer: true, in: 1..65_535 }, allow_nil: true
  validates :mail_from, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :subdomain, presence: true, uniqueness: true,
                        format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true

  scope :active, -> { where(archived_at: nil) }

  after_create_commit :ensure_signing_key!

  def public_origin
    template = Rails.configuration.masks.public_origin_template

    template && format(template, subdomain: subdomain).chomp("/")
  end

  def named_by
    self.class.pinned_names.presence || super.presence || EITHER
  end

  def names_pinned?
    self.class.pinned_names.present?
  end

  def mail_from
    super.presence || Rails.configuration.masks.mail_from
  end

  def own_smtp?
    self[:smtp_address].present?
  end

  def smtp_settings
    return ActionMailer::Base.smtp_settings if !own_smtp? && ActionMailer::Base.smtp_settings.present?
    return nil unless own_smtp?

    {
      address: smtp_address,
      port: smtp_port || SMTP_PORT,
      user_name: smtp_username.presence,
      password: smtp_password.presence,
      authentication: (smtp_authentication.presence || AUTHENTICATIONS.first).to_sym,
      domain: smtp_domain.presence,
      tls: smtp_tls,
      enable_starttls: !smtp_tls,
      openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER,
      open_timeout: SMTP_TIMEOUT,
      read_timeout: SMTP_TIMEOUT
    }.compact
  end

  def mails?
    mail_from.present? && smtp_settings.present?
  end

  def dynamic_registration
    self.class.pinned_registration.presence || super.presence || registration_unset
  end

  def registration_pinned?
    self.class.pinned_registration.present?
  end

  def registers?
    dynamic_registration != REGISTRATION_OFF
  end

  def registration_unset
    held = dynamic_client_scopes.presence || Rails.configuration.masks.dynamic_client_scopes

    held.present? ? REGISTRATION_BOUNDED : REGISTRATION_ANYTHING
  end

  def dynamic_client_ceiling
    return nil unless dynamic_registration == REGISTRATION_BOUNDED

    declared = dynamic_client_scopes.presence ||
      Rails.configuration.masks.dynamic_client_scopes

    Scopes.list(declared.presence || Scopes.join(Scopes::STANDARD))
  end

  class << self
    def pinned
      Rails.configuration.masks.tenant
    end

    def pinned_names
      Rails.configuration.masks.named_by
    end

    def pinned_registration
      Rails.configuration.masks.dynamic_registration
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
        active.find_by(subdomain: subdomain) || create!(subdomain: subdomain, name: subdomain)
      end
    end

    def claim(host)
      return nil if declared.any?
      return nil if exists?

      subdomain = host.to_s.split(".").first

      create!(subdomain: subdomain, name: subdomain)
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
