require_relative "sessions/device"
require_relative "sessions/structure"
require_relative "session_bag/abstract"
require_relative "session_bag/current"
require_relative "session_bag/check"
require_relative "session_bag/primitive"
require_relative "session_bag/device"

module Masks
  class Session
    include ActiveSupport::Delegation

    RAILS_SESSION_KEY = "rack.session"
    REQUEST_ID_KEY = "masks.request_id"
    DATA_KEY = "_masks"
    EXPIRY_KEY = "__expiry__"
    NO_EXPIRY = "never"

    attr_reader :env, :bag

    def initialize(env, **opts, &block)
      @env = env
      @data = rails_session || {}

      structure(&block) if block_given?
    end

    def request_id
      @request_id ||= SecureRandom.uuid
    end

    def structure(&block)
      @structure ||= Sessions::Structure.new(self)
      @structure.apply(&block) if block_given?
      @structure
    end

    def clean(*args)
      data = args.any? ? args.first : self.data
      expiry = data[EXPIRY_KEY]

      if expiry != request_id && data.key?(EXPIRY_KEY) &&
           Masks.time.expired?(expiry)
        data.clear
      end

      data.each { |k, v| clean(v) if v.is_a?(Hash) }
    end

    def data
      @data[DATA_KEY] ||= {}
    end

    def [](name)
      structure.bag(name).value
    end

    def []=(name, value)
      structure.bag(name).replace(value)
    end

    def refresh(name, *args)
      structure.bag(name).refresh(*args)
    end

    def method_missing(name, *args, **opts)
      if structure.bag?(name)
        structure.bag(name)
      else
        super
      end
    end

    def rails_request
      @rails_request ||= ActionDispatch::Request.new(env)
    end

    def rails_session
      env[RAILS_SESSION_KEY]
    end
  end
end
