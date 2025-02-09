module Masks
  class Scopes
    attr_reader :config

    OPENID = "openid"
    MANAGE = "masks:manage"

    def initialize(config)
      @config = config
    end

    def detail(name)
      data = get(name)

      case data
      when String
        data
      when Hash
        data["detail"]
      else
        nil
      end
    end

    def hidden?(name)
      case get(name)
      when Hash
        !!data["hidden"]
      else
        false
      end
    end

    def get(name)
      config&.fetch(name.to_s, nil)
    end
  end
end
