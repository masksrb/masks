module Masks
  class ClientPolicy
    include Policy
    include RequestMatchers

    def initialize(key = nil, **opts, &block)
      if block_given?
        super(**opts.merge(key: block))
      else
        super(**opts.merge(key: key))
      end
    end

    checks :request do |policy|
      key = case policy.config[:key]
      when Symbol, String, Proc
        key
      when nil
        Masks.mode.default_client
      end

      masks_session.client = case key
      when Symbol, String
        Masks.clients.find_by(key:)
      when Proc
        instance_exec(&key)
      end

      unless masks_session.client
        stop :not_found, status: 404, policy:, debug: "Client key=#{key} could not be found"
      end
    end
  end
end
