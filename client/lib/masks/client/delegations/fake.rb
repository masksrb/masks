require "masks/client"

module Masks
  module Client
    class Delegations
      class Fake
        Connected = Struct.new(:connection, :provider, :subject, :secret, :refused, :unavailable, keyword_init: true)

        attr_reader :releases, :redirect_uri

        def initialize(redirect_uri: "https://app.test/connect/callback", lifetime: 3600)
          @redirect_uri = redirect_uri
          @lifetime = lifetime
          @codes = {}
          @connections = {}
          @releases = 0
          @lock = Mutex.new
        end

        def start(provider:, prompt: nil, max_age: nil, state: SecureRandom.urlsafe_base64(24))
          query = URI.encode_www_form({ "provider" => provider, "state" => state, "prompt" => prompt, "max_age" => max_age }.compact)

          { "url" => "https://masks.fake/authorize?#{query}", "state" => state, "verifier" => SecureRandom.hex(16), "provider" => provider.to_s }
        end

        def approve(started, subject: "fake-subject", connection: SecureRandom.uuid)
          code = SecureRandom.hex(12)

          @lock.synchronize do
            @codes[code] = { "provider" => started["provider"], "subject" => subject, "connection" => connection }
          end

          { "code" => code, "state" => started["state"] }
        end

        def deny(started, error: "access_denied", description: "the person declined")
          { "error" => error, "error_description" => description, "state" => started["state"] }
        end

        def finish(params:, started:)
          params = params.to_h.transform_keys(&:to_s)

          raise Refused.new(params["error"], params["error_description"]) if params["error"].to_s != ""
          raise Refused.new("invalid_state", "the state did not match the one this connection started with") unless params["state"] == started["state"]

          granted = @lock.synchronize { @codes.delete(params["code"]) }

          raise Refused.new("invalid_grant", "that code is not valid") if granted.nil?

          secret = SecureRandom.hex(16)

          @lock.synchronize do
            @connections[granted["connection"]] = Connected.new(
              connection: granted["connection"], provider: granted["provider"], subject: granted["subject"], secret: secret
            )
          end

          Held.new(connection: granted["connection"], provider: granted["provider"], provider_name: granted["provider"].to_s.capitalize,
                   label: nil, subject: granted["subject"], secret: secret)
        end

        def token(secret, connection:)
          held = @lock.synchronize { @connections[connection.to_s] }

          raise Refused.new("invalid_grant", "that connection is unknown") if held.nil?
          raise Unavailable.new("masks is not answering", secret: secret) if held.unavailable
          raise Refused.new("invalid_grant", held.refused, secret: secret) if held.refused
          raise Refused.new("invalid_grant", "that refresh token is not valid or has expired") unless held.secret == secret.to_s

          rotated = SecureRandom.hex(16)

          @lock.synchronize do
            held.secret = rotated
            @releases += 1
          end

          Upstream.new(access_token: "#{held.provider}-access-#{@releases}", expires_at: Time.now.to_i + @lifetime,
                       scope: "", secret: rotated)
        end

        def revoke(connection, reason: "the person stopped this application using that account")
          @lock.synchronize { @connections.fetch(connection.to_s).refused = reason }
        end

        def unavailable(connection, now: true)
          @lock.synchronize { @connections.fetch(connection.to_s).unavailable = now }
        end
      end
    end
  end
end
