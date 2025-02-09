module Masks
  module Entries
    class Internal < Masks::Entry
      class << self
        def login(entry, token)
          entry
            .session
            .internal_token
            .with(entry.client) do |bag|
              bag["token"] = token.secret
              bag.refresh(token.expires_at)
            end

          session.internal_token.tap do |bag|
            bag.replace(session.client)
            bag["token"] = token.secret
            bag.refresh(token.expires_at)
          end

          session[:clients]["current_token"] = token.secret
        end

        def manager?(session)
          enter(session, managers_only: true, quiet: true).trusted?
        end
      end

      def client
        @client ||=
          (
            if raw_params[:managers_only]
              Masks.installation.management_client
            elsif raw_params[:client_id]
              Masks.client(raw_params[:client_id])
            else
              raw_params[:client]
            end
          )
      end

      def params
        {}
      end

      def actor
        @actor ||= load_for_client(client)
      end

      def manager
        @manager ||=
          begin
            manager = load_for_client(Masks.installation.management_client)
            manager if manager&.masks_manager?
          end
      end

      def trusted?
        raw_params[:managers_only] ? manager : actor
      end

      def redirect_uri
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

        return if raw_params[:quiet]

        raise Masks::LoggedOut, self unless trusted?
      end

      def login(token)
        raise unless token.is_a?(Masks::InternalToken)

        bag = session.internal_token.with(client)
        bag["token"] = token.secret
        bag.refresh(token.expires_at)
      end

      private

      def load_for_client(client)
        secret = session.internal_token.with(client)["token"]
        token =
          Masks::InternalToken.usable.find_by(
            device: session.current_device,
            client:,
            secret:,
          )
        session.internal_token.with(client).expire unless token
        token&.actor
      end
    end
  end
end
