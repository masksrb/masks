module Masks
  module Entries
    class Request < Masks::Entry
      class << self
        def env(env, **params)
          env["masks.request"] ||= enter(Masks::Session.env(env), **params)
        end
      end

      def client
        @client ||=
          if raw_params[:managers_only]
            install.management_client
          elsif raw_params[:block]
            instance_exec(&raw_params[:block])
          else
            case raw_params[:with]
            when String, Symbol
              Masks.client(raw_params[:with])
            when Masks::Client
              raw_params[:with]
            when Proc
              instance_exec(&raw_params[:with])
            when nil
              install.default_client
            end
          end
      end

      def params
        {}
      end

      def bearer_token
        @bearer_token ||=
          if raw_params[:bearer]
            header = rails_request.headers["Authorization"]
            prefix, token = header&.split(" ", 2) if header
            return unless prefix&.downcase == "bearer" && token&.present?
            Masks::AccessToken.find_by(secret: token)
          end
      end

      def token
        @token ||=
          begin
            token = bearer_token if raw_params[:bearer]
            token ||= internal_token if client.internal?
            token
          end
      end

      def actor
        token&.actor
      end

      def manager
        @manager ||=
          begin
            manager = internal_token(install.management_client)&.actor
            manager if manager&.masks_manager?
          end
      end

      def trusted?
        raw_params[:managers_only] ? manager : actor
      end

      def redirect_uri
        return unless client.internal?

        unless trusted?
          Rails.application.routes.url_helpers.masks_login_path(
            client_id: client.key,
            redirect_uri: session.rails_request.path,
          )
        end
      end

      def enter
        session[:actor] = actor
        session[:manager] = manager

        return if raw_params[:optional]

        raise Masks::LoggedOut, self unless trusted?
      end

      private

      def internal_token(client = nil)
        client ||= self.client

        # TODO: this is set in Promps::Internal. Clean it up and
        # use the Masks.installation (#install) to find the token.
        secret = session.internal_token.with(client)["token"]
        token =
          Masks::InternalToken.usable.find_by(
            device: session.current_device,
            client:,
            secret:,
          )
        session.internal_token.with(client).expire unless token
        token
      end
    end
  end
end
