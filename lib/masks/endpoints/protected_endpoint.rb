module Masks
  class ProtectedEndpoint
    include Masks::Endpoint

    class << self
      def structure(session)
        session.structure do
          key :token, parent: :client, expiry: Masks::NEVER_EXPIRE
        end
      end

      def login(session, token)
        structure(session)

        session.token.replace(token.secret)
        session.token.refresh(token.expires_at)
      end
    end

    def session_structure
      super

      self.class.structure(session)
    end

    def session_key
      "protected:#{opts[:section] || "masks"}"
    end

    def redirect_uri
      return if actor

      origin = session.rails_request.path

      if client.internal?
        Masks.rails_url(:masks_login, client, redirect_uri: origin)
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
            Masks.clients.discover(value)
          else
            value
          end
        end
    end

    def actor
      @actor ||=
        begin
          return if @actor_loaded

          actor = load_actor
          @actor_loaded = true

          if opts[:managers_only]
            actor if actor&.masks_manager?
          else
            actor
          end
        end
    end

    def call!
      raise Masks::Errors::MissingClient unless client

      if !opts[:optional] && !actor
        return [
          302,
          { "Location" => redirect_uri || "http://localhost:3000" },
          ""
        ]
      end

      session.rails_request.env["masks.session"] = session
      session.actor.current = actor

      nil
    end

    private

    def secret
      @secret ||=
        begin
          value = (session.token.value if client.internal?)

          value ||=
            rails_request.headers["Authorization"]&.delete_prefix(
              "Bearer",
            )&.strip if opts[:bearer_tokens]
          value
        end
    end

    def load_actor
      return unless secret

      client.find_token(device: session.device.current, secret:)&.actor
    end
  end
end
