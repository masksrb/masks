class Tenant < ApplicationRecord
  has_many :signing_keys, dependent: :destroy
  has_many :actors, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :tokens, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :consents, dependent: :destroy

  validates :subdomain, presence: true, uniqueness: true,
                        format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true

  scope :active, -> { where(archived_at: nil) }

  after_create_commit :ensure_signing_key!

  class << self
    def resolve(host)
      active.find_by(subdomain: host.to_s.split(".").first)
    end

    def declared
      Rails.configuration.masks.tenants
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

    def switch(tenant)
      raise ArgumentError, "no tenant" if tenant.nil?

      previous_tenant = Current.tenant

      ActiveRecord::Base.transaction(requires_new: true) do
        previous_setting = setting
        assign_setting(tenant.id)
        Current.tenant = tenant

        begin
          yield tenant
        ensure
          Current.tenant = previous_tenant
          assign_setting(previous_setting)
        end
      end
    end

    private

      def setting
        connection.select_value("SELECT current_setting('#{TenantIsolation::SETTING}', true)")
      end

      def assign_setting(id)
        connection.exec_query(
          "SELECT set_config('#{TenantIsolation::SETTING}', $1, true)", "tenant", [ id.to_s ]
        )
      rescue ActiveRecord::StatementInvalid
        nil
      end
  end

  def signing_key
    Tenant.switch(self) { signing_keys.active.first } || ensure_signing_key!
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
