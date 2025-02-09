module Masks
  class ClientScope
    attr_reader :client

    def initialize(client)
      @client = client
    end

    def minimum(scope)
      (ensure_array(scope) + required).uniq
    end

    def remove!(scopes)
      if scopes == "*"
        structure["required"] = []
        structure["allowed"] = []
      else
        structure["required"] = filter(scopes, structure["required"])
        structure["allowed"] = filter(scopes, structure["allowed"])
      end
    end

    def allow!(scopes)
      structure["required"] = filter(scopes, structure["required"])
      structure["allowed"] = combine(scopes, structure["allowed"])
    end

    def require!(scopes)
      structure["allowed"] = filter(scopes, structure["allowed"])
      structure["required"] = combine(scopes, structure["required"])
    end

    def required
      ensure_array(client.scopes&.dig("required"))
    end

    def all
      (required + ensure_array(client.scopes&.dig("allowed"))).uniq
    end

    private

    def combine(v1, v2)
      (ensure_array(v1) + ensure_array(v2)).uniq
    end

    def filter(scopes, from)
      v1 = ensure_array(scopes)
      v2 = ensure_array(from)
      v2 - v1
    end

    def structure
      if !client.scopes.is_a?(Hash) || !client.scopes["allowed"] ||
           !client.scopes["required"]
        client.scopes ||= { "required" => [], "allowed" => [] }
      end

      client.scopes
    end

    def ensure_array(scope)
      case scope
      when String
        scope.split(" ").map { |s| s.split(",") }.flatten
      when Array
        scope
      when nil
        []
      else
        raise "unknown scope type"
      end
    end
  end
end
