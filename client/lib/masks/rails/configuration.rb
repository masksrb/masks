module Masks
  module Rails
    class Configuration
      class Unconfigured < Masks::Client::Error; end

      attr_accessor :scope, :resource, :resource_scopes, :after_sign_in, :after_sign_out,
                    :session_key, :sign_out_of_issuer, :parent_controller,
                    :credentials_path, :authenticate_everything
      attr_writer :issuer, :redirect_uri, :name, :credentials, :store, :forget

      def initialize
        @scope = Masks::Client::Session::DEFAULT_SCOPE
        @resource_scopes = []
        @after_sign_in = "/"
        @after_sign_out = "/"
        @session_key = "masks"
        @sign_out_of_issuer = false
        @parent_controller = "ActionController::Base"
        @authenticate_everything = false
      end

      # An app that has not said where to keep its credentials gets one file
      # under the Rails root, so the handshake works before anybody writes a
      # `store` lambda. `things` overrides both because it is multi-tenant,
      # which is the interesting case rather than the common one.
      def default_credentials
        @default_credentials ||= Credentials.new(
          credentials_path || ::Rails.root.join("config", "masks.json")
        )
      end

      def name_for(request)
        resolve(@name, request).presence || ::Rails.application.class.module_parent_name
      end

      def issuer_for(request)
        resolve(@issuer, request) ||
          raise(Unconfigured, "Masks::Rails.config.issuer is not set")
      end

      def redirect_uri_for(request)
        resolve(@redirect_uri, request) ||
          "#{request.base_url}#{routes.callback_path}"
      end

      def resource_for(request)
        resolve(@resource, request)
      end

      def credentials_for(request)
        held = @credentials ? resolve(@credentials, request) : default_credentials.read
        held ||= {}

        held.respond_to?(:to_h) ? held.to_h.transform_keys(&:to_s) : {}
      end

      def client_id_for(request)
        credentials_for(request)["client_id"].presence
      end

      def client_secret_for(request)
        credentials_for(request)["client_secret"].presence
      end

      def configured?(request)
        client_id_for(request).present?
      end

      # An app that keeps its own credentials has to say how to drop them, and
      # until it does the engine does not offer a button it cannot honour.
      def can_forget?
        @forget.respond_to?(:call) || !@store.respond_to?(:call)
      end

      def forget!(request)
        return @forget.call(request) if @forget.respond_to?(:call)
        raise Unconfigured, "Masks::Rails.config.forget is not set" if @store.respond_to?(:call)

        default_credentials.clear!
      end

      def store!(request, registration)
        return default_credentials.write(registration) unless @store.respond_to?(:call)

        @store.call(request, registration)
      end

      # The engine depends on `handshake_endpoint` being in the discovery
      # document, and on the approval flow behind it. An issuer that predates
      # both should say so here rather than at the one screen that exists to
      # be the first thing anybody touches.
      MINIMUM_ISSUER = 1

      def issuer_speaks!(request)
        spoken = Masks::Client::Issuer.resolve(issuer_for(request))
                                     .discovery["masks_protocol_version"].to_i

        return true if spoken >= MINIMUM_ISSUER

        raise Unconfigured,
              "#{issuer_for(request)} speaks masks protocol #{spoken}, and masks " \
              "#{Masks::VERSION} needs at least #{MINIMUM_ISSUER}"
      end

      def session_for(request)
        raise Unconfigured, "this app has not shaken hands with #{issuer_for(request)}" unless configured?(request)

        Masks::Client::Session.new(
          issuer: issuer_for(request),
          client_id: client_id_for(request),
          client_secret: client_secret_for(request),
          redirect_uri: redirect_uri_for(request),
          scope: scope
        )
      end

      def resource_server_for(request)
        url = Array(resource_for(request)).first

        raise Unconfigured, "Masks::Rails.config.resource is not set" if url.nil?

        Masks::Client::Resource.new(
          issuer: issuer_for(request),
          url: url,
          scopes: resource_scopes
        )
      end

      def handshake_for(request)
        Masks::Client::Handshake.new(
          issuer_for(request),
          name: name_for(request),
          resource: Array(resource_for(request)).first ||
            raise(Unconfigured, "Masks::Rails.config.resource is not set"),
          redirect_uris: [ redirect_uri_for(request) ],
          return_to: return_to_for(request),
          scope: scope
        )
      end

      def return_to_for(request)
        uri = URI.parse(redirect_uri_for(request))
        port = ":#{uri.port}" unless uri.port == uri.default_port

        "#{uri.scheme}://#{uri.host}#{port}#{routes.handshake_callback_path}"
      end

      private

        def routes
          Masks::Rails::Engine.routes.url_helpers
        end

        def resolve(value, request)
          return value unless value.respond_to?(:call)

          value.arity.zero? ? value.call : value.call(request)
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
