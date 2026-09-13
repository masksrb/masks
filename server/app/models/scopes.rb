module Scopes
  OPENID = "openid".freeze
  PROFILE = "profile".freeze
  EMAIL = "email".freeze
  OFFLINE = "offline_access".freeze
  IDENTITIES = "identities".freeze
  MANAGE = "masks:manage".freeze
  HANDSHAKE = "masks:handshake".freeze
  DELEGATE = "masks:delegate:".freeze

  DESCRIBED = {
    OPENID => "openid",
    PROFILE => "profile",
    EMAIL => "email",
    OFFLINE => "offline_access",
    IDENTITIES => "identities",
    MANAGE => "manage",
    HANDSHAKE => "handshake"
  }.freeze

  STANDARD = [ OPENID, PROFILE, EMAIL, OFFLINE, IDENTITIES ].freeze
  NAMESPACE = "masks:".freeze

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

    def delegations(value)
      list(value).select { |scope| scope.start_with?(DELEGATE) && scope.length > DELEGATE.length }
    end

    def delegable(value)
      list(value).select { |scope| scope.start_with?(DELEGATE) }
    end

    def delegated_provider(scope)
      scope.to_s.delete_prefix(DELEGATE) if scope.to_s.start_with?(DELEGATE) && scope.to_s.length > DELEGATE.length
    end

    def reserved(value)
      list(value).select { |scope| scope.start_with?(NAMESPACE) }
    end

    def describe(value)
      list(value).map { |scope| [ scope, description_for(scope) ] }
    end

    def description_for(scope, locale: I18n.locale)
      return I18n.t("scopes.delegates", locale: locale) if scope == DELEGATE

      if prefix?(scope)
        return I18n.t("scopes.namespace", namespace: scope.chomp(":"), locale: locale)
      end

      if (provider = delegated_provider(scope))
        named = Provider.find_by(key: provider)&.name || provider
        return I18n.t("scopes.delegate", provider: named, locale: locale)
      end

      key = DESCRIBED[scope]
      return I18n.t("scopes.#{key}", locale: locale) if key

      I18n.t("scopes.generic", name: scope, locale: locale)
    end
  end
end
