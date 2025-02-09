module Masks
  module BasicEndpoint
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

    def request_id
      @request_id ||= SecureRandom.uuid
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

    def session_structure
      nil
    end

    # def url
    #   session.rails_request.url
    # end

    # def redirect_uri
    #   nil
    # end

    # def session
    #   @session ||= Masks.session(@env) if @env
    # end

    # def path
    #   session.rails_request.path
    # end

    # def settings
    #   {}
    # end

    # def warnings
    #   @warnings ||= []
    # end

    # def warn!(*keys)
    #   warnings << keys.compact.join(":")
    #   @warnings.uniq!
    # end

    # def extras(**additions)
    #   @extras ||= {}
    #   @extras.deep_merge!(additions)
    # end

    # def public_json
    #   json = {
    #     id: session_key,
    #     url:,
    #     request_id:,
    #     redirect_uri:,
    #     error:,
    #     warnings:,
    #     extras:,
    #     client: client&.public_json,
    #   }

    #   json[:settings] = Masks.conf.public_json
    #   json
    # end

    def call(env)
      @env = env

      session_structure
      session.clean

      response = respond
      response ? response : app.call(env)
    end
  end
end
