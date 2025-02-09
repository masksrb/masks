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

    EXPIRY_KEY = "__expiry__"

    class << self
      def env(env)
        env["masks.session"] ||= new(env)
      end
    end

    NO_EXPIRY = "never"
    SESSION_KEY = "_masks"

    attr_reader :env, :bag

    def initialize(env, &block)
      @env = env
      @bags = {}

      structure(&block) if block_given?
    end

    def deep_clean(data = nil)
      data ||= self.data
      expiry = data[EXPIRY_KEY]

      if expiry != request_id && data.key?(EXPIRY_KEY) &&
           Masks.time.expired?(expiry)
        data.clear
      end

      data.each { |k, v| deep_clean(v) if v.is_a?(Hash) }
    end

    def request_id
      env["masks.request_id"] ||= SecureRandom.uuid
    end

    def structure(&block)
      @structure ||= Sessions::Structure.new(self)
      @structure.apply(&block) if block_given?
      @structure
    end

    def data
      rails_session[SESSION_KEY] ||= {}
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
      if name.to_s.start_with?("current_")
        structure.bag(name.to_s.slice(8...))&.current
      elsif structure.bag?(name)
        structure.bag(name)
      else
        super
      end
    end

    def rails_request
      @rails_request ||= ActionDispatch::Request.new(env)
    end

    def rails_session
      @rails_session ||= env["rack.session"]
    end
  end
end
