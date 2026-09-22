class SignInPolicy < ApplicationRecord
  include TenantScoped
  include Archivable

  OFF = "off".freeze
  OPTIONAL = "optional".freeze
  REQUIRED = "required".freeze
  PRESENCE = [ OFF, OPTIONAL, REQUIRED ].freeze

  FIRST_FACTORS = %w[password passkey provider].freeze
  SECOND_FACTORS = %w[otp passkey backup_codes].freeze

  NONE = "none".freeze
  CODE = "code".freeze
  LINK = "link".freeze
  APPROVAL = "approval".freeze
  CONFIRMATIONS = [ NONE, CODE, LINK, APPROVAL ].freeze

  has_many :clients, dependent: :nullify

  validates :key, presence: true,
                  uniqueness: { scope: :tenant_id },
                  format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true
  validates :nickname, :email, :phone, inclusion: { in: PRESENCE }
  validates :confirmation, inclusion: { in: CONFIRMATIONS }
  validates :password_minimum, numericality: { only_integer: true, in: Actor::MINIMUM_PASSWORD..256 }
  validate :factors_are_known
  validate :something_names_an_account
  validate :confirmation_has_somewhere_to_go
  validate :hiding_needs_a_code
  validate :signup_scopes_stay_ordinary
  validate :a_default_keeps_a_local_way_in

  normalizes :email_domains, with: ->(held) {
    Array(held).map { |one| one.to_s.strip.downcase.delete_prefix("@") }.reject(&:empty?).uniq
  }

  class << self
    def default
      new(key: "default", name: "Default")
    end

    def first_run
      new(key: "first-run", name: "First run", signup: true, nickname: REQUIRED, email: REQUIRED, phone: OFF)
    end

    def for(client: nil, tenant: Current.tenant)
      [ client&.sign_in_policy, tenant&.sign_in_policy ].compact.find { |policy| !policy.archived? } || default
    end
  end

  def asks?(field)
    public_send(field) != OFF
  end

  def requires?(field)
    public_send(field) == REQUIRED
  end

  def first_factor?(factor)
    first_factors.include?(factor.to_s)
  end

  def local?
    first_factor?(:password) || first_factor?(:passkey)
  end

  def second_factor?(factor)
    second_factors.include?(factor.to_s)
  end

  def admits?(email)
    return true if email_domains.empty?

    domain = email.to_s.split("@").last.to_s.downcase

    email_domains.include?(domain)
  end

  def offers?(provider)
    providers.nil? || providers.include?(provider.key)
  end

  def signup_scope_list
    signup_scopes.present? ? Scopes.list(signup_scopes) : Scopes::STANDARD
  end

  private

    def factors_are_known
      errors.add(:first_factors, "must include at least one way to sign in") if first_factors.blank?

      unknown = Array(first_factors) - FIRST_FACTORS
      errors.add(:first_factors, "does not know #{unknown.join(', ')}") if unknown.any?

      unknown = Array(second_factors) - SECOND_FACTORS
      errors.add(:second_factors, "does not know #{unknown.join(', ')}") if unknown.any?

      if second_factor_required && (Array(second_factors) - [ "backup_codes" ]).empty?
        errors.add(:second_factors, "must offer an authenticator or a passkey when one is required")
      end
    end

    def something_names_an_account
      if nickname == OFF && email == OFF
        errors.add(:base, "An account needs a nickname or an email")
      end

      case tenant&.named_by
      when Tenant::NICKNAME
        errors.add(:nickname, "is required, because this tenant names accounts by nickname") unless requires?(:nickname)
      when Tenant::EMAIL
        errors.add(:email, "is required, because this tenant names accounts by email") unless requires?(:email)
      end
    end

    def confirmation_has_somewhere_to_go
      return unless [ CODE, LINK ].include?(confirmation)

      errors.add(:confirmation, "by email needs the email to be required") unless requires?(:email)
    end

    def hiding_needs_a_code
      return unless hidden

      errors.add(:hidden, "needs the email to be required") unless requires?(:email)
    end

    def a_default_keeps_a_local_way_in
      return if local? || !persisted?
      return unless Tenant.exists?(sign_in_policy_id: id)

      errors.add(:first_factors, "must keep a password or a passkey while this is the tenant's default, so managers are never locked out")
    end

    def signup_scopes_stay_ordinary
      reserved = Scopes.reserved(signup_scopes)

      errors.add(:signup_scopes, "may not include #{Scopes.join(reserved)}") if reserved.any?
    end
end
