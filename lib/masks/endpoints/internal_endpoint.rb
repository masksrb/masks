module Masks
  class InternalEndpoint
    include Masks::Endpoint

    class << self
      def structure(session)
        session.structure do
          unless bag?(:internal_token)
            current :internal_token,
                    parent: :device,
                    expiry: Masks::NEVER_EXPIRE,
                    null: true
          end
        end
      end

      def login(session)
        return unless session.structure.bag?(:oauth_request)

        client = session.current_client
        oauth = session.current_oauth_request

        if token = oauth.internal_token
          bag = session.internal_token.with(client)
          bag["token"] = token.secret
          bag.refresh(token.expires_at)
        end
      end
    end

    def session_key
      opts[:section] || "internal"
    end

    def trusted?
      actor
    end

    def redirect_uri
      unless trusted?
        Rails.application.routes.url_helpers.masks_login_path(
          client_id: client&.key,
          redirect_uri: path,
        )
      end
    end

    def client
      @client ||=
        begin
          value =
            if opts[:managers_only]
              Masks.conf.management_client
            elsif opts[:client_id]
              opts[:client_id]
            elsif block
              instance_exec(&block)
            else
              opts[:client]
            end

          case value
          when String
            Masks.clients.discover(value, internal: true)
          when Masks::Client
            value
          end
        end
    end

    def actor
      @actor ||=
        begin
          return if @actor_loaded

          actor = actor_for_client(client)
          @actor_loaded = true

          if opts[:managers_only]
            actor if actor&.masks_manager?
          else
            actor
          end
        end
    end

    def call!
      if !opts[:optional] && !trusted?
        return 302, { "Location" => redirect_uri }, ""
      end

      session[:actor] = actor

      nil
    end

    private

    def actor_for_client(client)
      token_for_client(client)&.actor
    end

    def token_for_client(client)
      self.class.structure(session)

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
