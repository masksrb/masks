module Masks
  class Scopes
    attr_reader :config

    OPENID = "openid"
    MANAGE = "masks:manage"

    def initialize(config)
      @config = config.stringify_keys
    end

    def map(scopes)
      scopes.map { |scope| json(scope) } if scopes
    end

    def detail(name)
      lookup(name)[:detail]
    end

    def hidden?(name)
      value = lookup(name)
      value.key?(:hidden) ? value[:hidden] : true
    end

    def json(name)
      data = lookup(name)
      data.merge(hidden: hidden?(name))
    end

    def lookup(name)
      name = name.to_s

      @lookups ||= {}
      @lookups[name] ||= begin
        data = config&.fetch(name, nil)
        hash = { scope: name, name: }

        case data
        when String
          hash[:detail] = data
        when Hash
          hash.merge!(**data.symbolize_keys)
        end

        hash
      end

      @lookups[name]
    end
  end
end
