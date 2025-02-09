module Masks
  module Endpoint
    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      attr_accessor :settings
    end

    class_methods do
      def request(*args, **opts)
        e = new(*args, **opts)
        e.request!
      ensure
        e
      end
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

    delegate :request_id, to: :session, allow_nil: true

    def url
      session.rails_request.url
    end

    def redirect_uri
      nil
    end

    def session
      Masks::Session.env(@env) if @env
    end

    def path
      session.rails_request.path
    end

    def client
      raise NotImplementedError
    end

    def session_key
      raise NotImplementedError
    end

    def session_lifetime
      nil
    end

    def settings
      {}
    end

    def warnings
      @warnings ||= []
    end

    def warn!(*keys)
      warnings << keys.compact.join(":")
      @warnings.uniq!
    end

    def extras(**additions)
      @extras ||= {}
      @extras.deep_merge!(additions)
      @extras
    end

    def public_json
      json = {
        id: session_key,
        url:,
        request_id:,
        redirect_uri:,
        error:,
        warnings:,
        extras:,
        client: client&.public_json,
      }

      json[:settings] = Masks.conf.public_json
      json
    end

    def call(env)
      @env = env

      device_class = Masks.conf.device_class.constantize

      session.structure do
        unless bag?(:device)
          device device_class,
                 expiry: device_class.cleanup_at || Masks::NEVER_EXPIRE
        end

        unless bag?(:client)
          current :client, parent: :device, expiry: Masks::NEVER_EXPIRE
        end

        unless bag?(:endpoint)
          current :endpoint, parent: :device # expiry is pulled from session_lifetime
        end

        unless bag?(:actor)
          current :actor, parent: :device, expiry: Masks::NEVER_EXPIRE
        end
      end

      session[:endpoint] = self
      session[:client] = client if client

      response = call!

      session.deep_clean
      session.device.refresh

      response ? response : app.call(env)
    end
  end
end
