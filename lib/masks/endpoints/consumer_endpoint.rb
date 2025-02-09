module Masks
  class ConsumerEndpoint
    include Masks::Endpoint

    class << self

    end

    def session_key
      "masks:#{opts[:section] || "masks:consumer"}"
    end

    def redirect_uri
      client&.generate_redirect(origin: path) unless actor
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

      session[:actor] = actor

      nil
    end

    private

    # def actor_for_client(client)
    #   token_for_client(client)&.actor
    # end

    # def token_for_client(client)
    #   if Masks.mode.server?
    #     internal_token(client) if client.internal?
    #   else
    #     consumer_token(client)
    #   end
    # end

    def internal_token
      return unless Masks.mode.server? && client.internal?

      self.class.internal_structure(session)

      client.find_token(
        secret: session.internal_token.with(client)["token"],
        device: session.current_device,
      )
    end

    def consumer_token
      return unless Masks.mode.consumer? || client.supports_oauth?

      secret = session.consumer_token.with(client)["token"]
      token =
        Masks.tokens.for_consumer(
          secret,
          device: session.current_device,
          client:,
        )

      session.internal_token.with(client).expire unless token
      token
    end

    def server_token(client)
      self.class.internal_structure(session)
    end
  end
end
