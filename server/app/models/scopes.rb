module Scopes
  OPENID = "openid".freeze
  PROFILE = "profile".freeze
  EMAIL = "email".freeze
  OFFLINE = "offline_access".freeze
  MANAGE = "masks:manage".freeze
  HANDSHAKE = "masks:handshake".freeze

  DESCRIBED = {
    OPENID => "openid",
    PROFILE => "profile",
    EMAIL => "email",
    OFFLINE => "offline_access",
    MANAGE => "manage",
    HANDSHAKE => "handshake"
  }.freeze

  STANDARD = [ OPENID, PROFILE, EMAIL, OFFLINE ].freeze
  NAMESPACE = "masks:".freeze
  CONNECTIONS = "masks:connections:".freeze

  class << self
    def list(value)
      case value
      when nil then []
      when Array then value
      else value.to_s.split(/[\s,]+/)
      end.map(&:to_s).reject(&:empty?).uniq.sort
    end

    def join(value)
      list(value).join(" ")
    end

    def prefix?(scope)
      scope.to_s.end_with?(":")
    end

    def covered?(available, scope)
      return false if prefix?(scope)
      return true if list(available).include?(scope)

      list(available).any? do |entry|
        prefix?(entry) && scope.start_with?(entry) && scope.length > entry.length
      end
    end

    def refused(available, requested)
      list(requested).reject { |scope| covered?(available, scope) }
    end

    def granted(requested, available)
      list(requested).select { |scope| covered?(available, scope) }
    end

    def union(*values)
      list(values.flat_map { |value| list(value) })
    end

    def covers?(available, requested)
      refused(available, requested).empty?
    end

    def reserved(value)
      list(value).select { |scope| scope.start_with?(NAMESPACE) }
    end

    def connection(provider_key)
      "#{CONNECTIONS}#{provider_key}"
    end

    def connection?(scope)
      scope.to_s.start_with?(CONNECTIONS) && scope.to_s.length > CONNECTIONS.length
    end

    def provider_key(scope)
      return nil unless connection?(scope)

      scope.to_s.delete_prefix(CONNECTIONS)
    end

    def describe(value)
      list(value).map { |scope| [ scope, description_for(scope) ] }
    end

    def description_for(scope, locale: I18n.locale)
      if prefix?(scope)
        return I18n.t("scopes.namespace", namespace: scope.chomp(":"), locale: locale)
      end

      key = DESCRIBED[scope]
      return I18n.t("scopes.#{key}", locale: locale) if key

      described_connection(scope, locale: locale) ||
        I18n.t("scopes.generic", name: scope, locale: locale)
    end

    def described_connection(scope, locale: I18n.locale)
      key = provider_key(scope)
      return nil if key.nil?

      name = Provider.active.find_by(key: key)&.name || key

      I18n.t("scopes.connection", provider: name, locale: locale)
    end
  end
end
