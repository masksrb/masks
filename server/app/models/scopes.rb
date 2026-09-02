module Scopes
  OPENID = "openid".freeze
  PROFILE = "profile".freeze
  EMAIL = "email".freeze
  OFFLINE = "offline_access".freeze
  MANAGE = "masks:manage".freeze

  DESCRIBED = {
    OPENID => "Confirm who you are",
    PROFILE => "Read your name and nickname",
    EMAIL => "Read your email address",
    OFFLINE => "Stay signed in when you are away",
    MANAGE => "Modify the masks backend"
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

    def granted(requested, available)
      list(requested) & list(available)
    end

    def union(*values)
      list(values.flat_map { |value| list(value) })
    end

    def covers?(available, requested)
      (list(requested) - list(available)).empty?
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
      list(value).map { |scope| [ scope, DESCRIBED[scope] || described_connection(scope) ] }
    end

    def described_connection(scope)
      key = provider_key(scope)
      return nil if key.nil?

      name = Provider.active.find_by(key: key)&.name || key

      "Use your #{name} account on your behalf"
    end
  end
end
