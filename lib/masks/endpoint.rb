module Masks
  module Endpoint
    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      attr_accessor :settings
    end

    attr_accessor :app
    attr_accessor :args
    attr_accessor :opts
    attr_accessor :block
    attr_accessor :error

    def initialize(app = nil, *args, **opts, &block)
      self.app = app
      self.args = args
      self.opts = opts
      self.block = block
    end

    delegate :request_id, to: :session

    def client
      raise NotImplementedError
    end

    def session_key
      raise NotImplementedError
    end

    def session_structure
      session.structure do
        cls = Masks.devices

        device cls, expiry: cls.cookie_expiry || Masks::NEVER_EXPIRE

        current :client, parent: :device, expiry: Masks::NEVER_EXPIRE
        current :actor, parent: :device, expiry: Masks::NEVER_EXPIRE
        current :endpoint, parent: :device # expiry is pulled from session_lifetime
      end
    end

    def session
      @session ||= Masks.session(@env) if @env
    end

    def call(env)
      @env = env

      session_structure

      session.endpoint.current = self
      session.client.current = client if client

      response = call!

      session.device.refresh
      session.clean

      response ? response : @app.call(@env)
    end
  end
end
