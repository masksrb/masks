module Scopes
  OPENID = "openid".freeze
  PROFILE = "profile".freeze
  EMAIL = "email".freeze
  OFFLINE = "offline_access".freeze

  DESCRIBED = {
    OPENID => "Confirm who you are",
    PROFILE => "Read your name and nickname",
    EMAIL => "Read your email address",
    OFFLINE => "Stay signed in when you are away"
  }.freeze

  STANDARD = DESCRIBED.keys.freeze

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

    def describe(value)
      list(value).map { |scope| [ scope, DESCRIBED[scope] ] }
    end
  end
end
