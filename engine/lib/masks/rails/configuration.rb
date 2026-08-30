module Masks
  module Rails
    class Configuration
      attr_accessor :client_id, :client_secret, :scope, :resource,
                    :after_sign_in, :after_sign_out, :session_key
      attr_writer :issuer, :redirect_uri

      def initialize
        @scope = Masks::Client::Session::DEFAULT_SCOPE
        @after_sign_in = "/"
        @after_sign_out = "/"
        @session_key = "masks"
      end

      def issuer_for(request)
        resolve(@issuer, request) ||
          raise(Masks::Client::Error, "Masks::Rails.config.issuer is not set")
      end

      def redirect_uri_for(request)
        resolve(@redirect_uri, request) ||
          "#{request.base_url}#{Masks::Rails::Engine.routes.url_helpers.callback_path}"
      end

      def resource_for(request)
        resolve(@resource, request)
      end

      def client_id_for(request)
        resolve(@client_id, request)
      end

      def client_secret_for(request)
        resolve(@client_secret, request)
      end

      def session_for(request)
        Masks::Client::Session.new(
          issuer: issuer_for(request),
          client_id: client_id_for(request),
          client_secret: client_secret_for(request),
          redirect_uri: redirect_uri_for(request),
          scope: scope
        )
      end

      private

        def resolve(value, request)
          value.respond_to?(:call) ? value.call(request) : value
        end
    end

    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield config
        config
      end
    end
  end
end
