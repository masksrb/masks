class Adapter < ApplicationRecord
  class Failed < StandardError; end

  include TenantScoped

  Field = Data.define(:key, :label, :type, :secret, :required, :options, :default, :hint)

  MAIL = "mail".freeze
  SMS = "sms".freeze
  KINDS = [ MAIL, SMS ].freeze

  encrypts :secrets

  validates :key, presence: true,
                  uniqueness: { scope: :tenant_id },
                  format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :fields_are_filled
  validate :options_are_offered

  before_validation { self.kind = self.class.kind }

  scope :active, -> { where(archived_at: nil) }

  class << self
    attr_writer :kind, :label

    def kind
      @kind || superclass.try(:kind)
    end

    def label
      @label || service.titleize
    end

    def service
      name.demodulize.underscore
    end

    def field(key, label:, type: :string, secret: false, required: true, options: nil, default: nil, hint: nil)
      own_fields << Field.new(key.to_s, label, type.to_s, secret, required, options, default, hint)
    end

    def fields
      (superclass.respond_to?(:fields) ? superclass.fields : []) + own_fields
    end

    def own_fields
      @own_fields ||= []
    end

    def services
      [
        Adapters::Smtp,
        Adapters::Twilio, Adapters::Vonage, Adapters::Plivo, Adapters::Telnyx, Adapters::Sinch,
        Adapters::MessageBird, Adapters::Infobip, Adapters::Sns, Adapters::ClickSend,
        (Adapters::SmsLog if Rails.env.local?)
      ].compact
    end

    def service_for(name)
      services.find { |klass| klass.service == name.to_s }
    end

    def primary(kind)
      active.find_by(kind: kind, primary: true)
    end
  end

  def service
    self.class.service
  end

  def archived?
    archived_at.present?
  end

  def [](key)
    field = self.class.fields.find { |held| held.key == key.to_s }
    return nil if field.nil?

    value = field.secret ? secret_values[field.key] : (settings || {})[field.key]

    value.nil? ? field.default : value
  end

  def configure(values)
    values = (values || {}).to_h.stringify_keys
    plain = (settings || {}).dup
    hidden = secret_values.dup

    self.class.fields.each do |field|
      next unless values.key?(field.key)

      value = cast(field, values[field.key])

      if field.secret
        next if value.blank?

        hidden[field.key] = value
      else
        plain[field.key] = value
      end
    end

    self.settings = plain
    self.secrets = hidden.to_json
    self
  end

  def secrets_held
    self.class.fields.select { |field| field.secret && secret_values[field.key].present? }.map(&:key)
  end

  def public_settings
    self.class.fields.reject(&:secret).to_h { |field| [ field.key, self[field.key] ] }
  end

  def deliver_test(to)
    raise NotImplementedError
  end

  private

    def secret_values
      @secret_values = nil if @secret_source != secrets
      @secret_source = secrets
      @secret_values ||= secrets.present? ? JSON.parse(secrets) : {}
    rescue JSON::ParserError
      {}
    end

    def cast(field, value)
      case field.type
      when "boolean" then ActiveModel::Type::Boolean.new.cast(value) || false
      when "integer" then value.presence && value.to_i
      else value.to_s.strip.presence
      end
    end

    def fields_are_filled
      self.class.fields.each do |field|
        next unless field.required
        next if field.type == "boolean"

        errors.add(:base, "#{field.label} is required") if self[field.key].blank?
      end
    end

    def options_are_offered
      self.class.fields.each do |field|
        next if field.options.nil? || self[field.key].blank?

        errors.add(:base, "#{field.label} must be one of #{field.options.join(', ')}") unless
          field.options.include?(self[field.key])
      end
    end
end
