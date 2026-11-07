require "masks/client"
require "monitor"
require "socket"

module Masks
  module Client
    class Fake
      ALGORITHM = "RS256".freeze
      UPSTREAM = "urn:masks:params:oauth:token-type:upstream_access_token".freeze
      TENANT = { "uuid" => "t-1", "subdomain" => "demo", "name" => "Demo" }.freeze
      SCOPE = "openid profile email".freeze
      AUDIENCE = "https://app.test/mcp".freeze
      PNG = "\x89PNG fake photo".b.freeze
      REASONS = { 200 => "OK", 201 => "Created", 204 => "No Content", 302 => "Found", 400 => "Bad Request",
                  401 => "Unauthorized", 404 => "Not Found", 503 => "Service Unavailable" }.freeze
      PEOPLE = {
        "ada" => {
          "name" => "Ada Lovelace",
          "preferred_username" => "ada",
          "email" => "ada@example.com",
          "email_verified" => true,
          "orgs" => [
            { "id" => "o-1", "key" => "acme", "name" => "Acme", "role" => "owner" },
            { "id" => "o-2", "key" => "globex", "name" => "Globex", "role" => "member" }
          ]
        },
        "bob" => {
          "name" => "Bob",
          "preferred_username" => "bob",
          "email" => "bob@example.com",
          "email_verified" => false,
          "orgs" => [ { "id" => "o-1", "key" => "acme", "name" => "Acme", "role" => "member" } ]
        }
      }.freeze

      Registered = Struct.new(:method, :secret, :jwks, :scope, :metadata, keyword_init: true)

      attr_reader :key, :kid, :port, :tenant, :people, :requests, :received, :clients, :codes, :grants, :initial,
                  :registrations, :enrolled, :revoked, :handshakes, :exchanges, :authorized
      attr_accessor :audience, :scope, :lifetime, :auth_time, :pending, :nonce, :foreign_uri, :backchannel,
                    :photo, :photo_type

      def self.start(**options)
        new(**options)
      end

      def initialize(tenant: TENANT, audience: AUDIENCE, scope: SCOPE)
        @key = OpenSSL::PKey::RSA.generate(2048)
        @kid = SecureRandom.uuid
        @tenant = tenant
        @audience = audience
        @scope = scope
        @lifetime = 3600
        @pending = 0
        @slowed = false
        @foreign_uri = false
        @backchannel = true
        @photo = PNG
        @photo_type = "image/png"
        @people = PEOPLE.transform_values { |person| JSON.parse(JSON.generate(person)) }
        @requests = Hash.new(0)
        @received = []
        @overrides = {}
        @clients = {}
        @codes = {}
        @grants = {}
        @initial = {}
        @registrations = {}
        @enrolled = {}
        @assertions = {}
        @revoked = []
        @handshakes = []
        @exchanges = []
        @lock = Monitor.new
        @server = TCPServer.new("127.0.0.1", 0)
        @port = @server.addr[1]
        @thread = Thread.new { serve }
      end

      def url
        "http://127.0.0.1:#{port}"
      end

      def stop
        @thread.kill
        @server.close
      rescue IOError
        nil
      end

      def count(path)
        @lock.synchronize { @requests[path] }
      end

      def last(path)
        @lock.synchronize { @received.reverse.find { |held| held[:path] == path } }
      end

      def override(path, body)
        @lock.synchronize { @overrides[path] = body }
      end

      def add(client_id, method: "client_secret_basic", secret: nil, jwks: nil, scope: nil)
        jwks = jwks.jwks if jwks.is_a?(Key)

        @lock.synchronize do
          @clients[client_id] = Registered.new(method: method, secret: secret, jwks: jwks || { "keys" => [] },
                                               scope: scope, metadata: {})
        end
      end

      def person(subject)
        held = @people[subject] || {}

        { "sub" => subject }.merge(held).merge(
          "tenant" => tenant,
          "masks:avatars" => { "photo" => "#{url}/avatars/#{subject}/photo", "identicon" => "#{url}/avatars/#{subject}/identicon" }
        )
      end

      def jwks
        { "keys" => [ public_jwk ] }
      end

      def public_jwk
        JWT::JWK.new(key, { kid: kid, use: "sig", alg: ALGORITHM }).export
      end

      def discovery
        {
          "issuer" => url,
          "tenant" => tenant,
          "authorization_endpoint" => "#{url}/authorize",
          "token_endpoint" => "#{url}/token",
          "userinfo_endpoint" => "#{url}/userinfo",
          "jwks_uri" => "#{url}/.well-known/jwks.json",
          "registration_endpoint" => "#{url}/register",
          "enrollment_endpoint" => "#{url}/enrollments",
          "device_authorization_endpoint" => "#{url}/device_authorization",
          "handshake_endpoint" => "#{url}/handshake",
          "revocation_endpoint" => "#{url}/revoke",
          "introspection_endpoint" => "#{url}/introspect",
          "end_session_endpoint" => "#{url}/logout",
          "authorization_response_iss_parameter_supported" => true,
          "backchannel_logout_supported" => backchannel
        }
      end

      def sign(claims, kid: self.kid, key: self.key, typ: "JWT")
        JWT.encode(claims, key, ALGORITHM, { kid: kid, typ: typ })
      end

      def access_token(subject: "ada", scope: self.scope, audience: self.audience, expires_in: lifetime, **extra)
        sign({
          "iss" => url,
          "sub" => subject,
          "aud" => audience,
          "exp" => Time.now.to_i + expires_in,
          "iat" => Time.now.to_i,
          "jti" => SecureRandom.uuid,
          "scope" => scope,
          "tenant" => tenant
        }.merge(extra.transform_keys(&:to_s)).compact, typ: Verifier::ACCESS_TOKEN)
      end

      def logout_token(client_id, subject: "ada", sid: nil, **changes)
        now = Time.now.to_i
        claims = {
          "iss" => url,
          "aud" => client_id,
          "iat" => now,
          "exp" => now + 120,
          "jti" => SecureRandom.uuid,
          "events" => { Logout::EVENT => {} },
          "sub" => subject,
          "sid" => sid
        }.merge(changes.transform_keys(&:to_s))

        sign(claims.compact, typ: Verifier::LOGOUT_TOKEN)
      end

      def authorize(target, subject: "ada", organization: nil, error: nil, state: nil, iss: nil)
        pairs = URI.decode_www_form(URI.parse(target).query.to_s)
        asked = pairs.to_h
        back = URI.parse(asked.fetch("redirect_uri"))

        @lock.synchronize do
          @authorized = asked

          if error
            answer = [ [ "error", error ], [ "error_description", "declined in the fake" ], [ "state", asked["state"] ] ]
          else
            code = SecureRandom.hex(16)
            @codes[code] = {
              "client_id" => asked["client_id"],
              "redirect_uri" => asked["redirect_uri"],
              "challenge" => asked["code_challenge"],
              "nonce" => asked["nonce"],
              "scope" => asked["scope"].to_s,
              "resource" => pairs.select { |name, _| name == "resource" }.map(&:last),
              "organization" => organization || asked["organization"],
              "subject" => subject,
              "sid" => "sid-#{SecureRandom.hex(8)}"
            }
            answer = [ [ "code", code ], [ "state", state || asked["state"] ], [ "iss", iss || url ] ]
          end

          back.query = [ back.query, URI.encode_www_form(answer) ].compact.join("&")
          back.to_s
        end
      end

      def handshake(target, error: nil, state: nil, iss: nil)
        asked = URI.decode_www_form(URI.parse(target).query.to_s).to_h
        back = URI.parse(asked.fetch("return_to"))

        @lock.synchronize do
          @handshakes << asked

          if error
            answer = [ [ "error", error ], [ "error_description", "declined in the fake" ], [ "state", asked["state"] ] ]
          else
            token = SecureRandom.hex(16)
            @initial[token] = "app-#{SecureRandom.hex(6)}"
            answer = [ [ "initial_access_token", token ], [ "iss", iss || url ], [ "state", state || asked["state"] ] ]
          end

          back.query = [ back.query, URI.encode_www_form(answer) ].compact.join("&")
          back.to_s
        end
      end

      private

        def serve
          loop do
            socket = @server.accept
            Thread.new { respond(socket) }
          end
        rescue IOError, Errno::EBADF
          nil
        end

        def respond(socket)
          line = socket.gets.to_s
          headers = {}

          while (header = socket.gets) && header.strip != ""
            name, value = header.split(":", 2)
            headers[name.to_s.strip.downcase] = value.to_s.strip
          end

          method, path = line.split(" ")
          length = headers["content-length"].to_i
          raw = length.positive? ? socket.read(length).to_s : ""
          pairs = form_pairs(raw)
          request = { method: method, path: path, headers: headers, body: parse(raw, pairs), pairs: pairs }

          status, body, extra = @lock.synchronize do
            @requests[path] += 1
            @received << request
            answer(request)
          end

          socket.print rendered(status, body, extra)
        ensure
          socket.close rescue nil
        end

        def rendered(status, body, extra)
          extra = Hash(extra)
          typed = extra.keys.any? { |name| name.to_s.casecmp?("content-type") }
          payload = body.is_a?(String) ? body : JSON.generate(body)
          lines = [ "HTTP/1.1 #{status} #{REASONS.fetch(status, 'OK')}" ]

          lines << "Content-Type: application/json" unless typed || body.nil?
          lines << "Content-Length: #{body.nil? ? 0 : payload.bytesize}"
          lines << "Connection: close"
          extra.each { |name, value| lines << "#{name}: #{value}" }

          (lines + [ "", body.nil? ? "" : payload ]).join("\r\n")
        end

        def form_pairs(raw)
          URI.decode_www_form(raw)
        rescue ArgumentError
          []
        end

        def parse(raw, pairs)
          JSON.parse(raw)
        rescue JSON::ParserError
          pairs.each_with_object({}) { |(name, value), held| held[name] = value }
        rescue StandardError
          {}
        end

        def answer(request)
          return canned(request) if @overrides.key?(request[:path])

          path, query = request[:path].to_s.split("?", 2)

          case [ request[:method], path ]
          when [ "GET", "/.well-known/openid-configuration" ] then [ 200, discovery ]
          when [ "GET", "/.well-known/jwks.json" ] then [ 200, jwks ]
          when [ "POST", "/token" ] then token(request)
          when [ "POST", "/device_authorization" ] then device(request)
          when [ "POST", "/revoke" ] then revoke(request)
          when [ "POST", "/introspect" ] then introspect(request)
          when [ "POST", "/register" ] then register(request)
          when [ "POST", "/enrollments" ] then enroll(request)
          when [ "GET", "/userinfo" ] then userinfo(request)
          when [ "GET", "/authorize" ] then [ 302, nil, { "Location" => authorize("#{url}#{request[:path]}") } ]
          when [ "GET", "/handshake" ] then [ 302, nil, { "Location" => handshake("#{url}#{request[:path]}") } ]
          when [ "GET", "/logout" ] then end_session(query)
          else routed(request, path)
          end
        end

        def routed(request, path)
          if path.start_with?("/register/")
            registration(request, URI.decode_www_form_component(path.delete_prefix("/register/")))
          elsif request[:method] == "DELETE" && path.start_with?("/enrollments/")
            unenroll(request, URI.decode_www_form_component(path.delete_prefix("/enrollments/")))
          elsif request[:method] == "GET" && path.start_with?("/avatars/")
            avatar(request)
          else
            [ 404, { "error" => "not_found" } ]
          end
        end

        def canned(request)
          found = @overrides[request[:path]]
          found = found.call(request[:body]) if found.respond_to?(:call)
          status, found, extra = found.is_a?(Array) ? found : [ found ? 200 : 404, found ]

          [ status, found || { "error" => "not_found" }, extra ]
        end

        def refused(status, code, extra = nil)
          [ status, { "error" => code, "error_description" => "#{code} from the fake" }, extra ]
        end

        def resources(request)
          request[:pairs].select { |name, _| name == "resource" }.map(&:last)
        end

        def decoded(token)
          return nil if token.to_s.empty? || @revoked.include?(token)

          JWT.decode(token, key, true, algorithms: [ ALGORITHM ], verify_aud: false).first
        rescue JWT::DecodeError
          nil
        end

        def authenticated(request)
          header = request[:headers]["authorization"].to_s
          form = request[:body]

          if header.start_with?("Basic ")
            id, secret = Base64.decode64(header[6..]).split(":", 2).map { |part| URI.decode_www_form_component(part.to_s) }
            client = @clients[id]

            return [ id, client, !client.nil? && client.method == "client_secret_basic" && client.secret == secret ]
          end

          id = form["client_id"]
          client = @clients[id]

          return [ id, nil, false ] if client.nil?

          allowed = case client.method
          when "client_secret_post" then form["client_secret"] == client.secret
          when "none" then true
          when "private_key_jwt" then asserted?(form, id, client)
          else false
          end

          [ id, client, allowed ]
        end

        def asserted?(form, id, client)
          return false unless form["client_assertion_type"] == Session::ASSERTION_TYPE

          claims, = JWT.decode(form["client_assertion"].to_s, nil, true,
                               algorithms: [ "ES256" ], jwks: client.jwks, aud: [ url, "#{url}/token" ], verify_aud: true,
                               iss: id, verify_iss: true, sub: id, verify_sub: true)

          return false if claims["jti"].to_s.empty? || @assertions[claims["jti"]]
          return false if claims["exp"].to_i - claims["iat"].to_i > 3600

          @assertions[claims["jti"]] = true
        rescue JWT::DecodeError, JWT::JWKError
          false
        end

        def proof(request, method, path, access_token: nil)
          presented = request[:headers]["dpop"]

          return [ nil, true ] if presented.nil?

          header = JWT.decode(presented, nil, false).last
          jwk = header["jwk"]

          return [ nil, false ] unless header["typ"].to_s.casecmp?(Proof::TYPE) && Proof::ALGORITHMS.include?(header["alg"].to_s)
          return [ nil, false ] unless jwk.is_a?(Hash) && (jwk.keys & Proof::SECRET).empty?

          claims = JWT.decode(presented, JWT::JWK.new(jwk).verify_key, true, algorithms: [ header["alg"] ]).first

          return [ nil, false ] unless claims["htm"] == method && claims["htu"] == "#{url}#{path}"
          return [ nil, false ] unless access_token.nil? ? !claims.key?("ath") : claims["ath"] == Proof.digest(access_token)
          return [ nil, false ] if nonce && claims["nonce"] != nonce

          [ Proof.thumbprint(jwk), true ]
        rescue JWT::DecodeError, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
          [ nil, false ]
        end

        def token(request)
          form = request[:body]
          jkt, proven = proof(request, "POST", "/token")

          return refused(400, "use_dpop_nonce", { "DPoP-Nonce" => nonce }) if !proven && nonce
          return refused(400, "invalid_dpop_proof") unless proven

          id, client, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed

          case form["grant_type"]
          when "client_credentials"
            signed_in(grant(id, id, form["scope"] || client.scope, resources(request)), id, jkt)
          when "authorization_code" then redeem(request, id, jkt)
          when "refresh_token" then refreshed(request, id, jkt)
          when Device::GRANT_TYPE then polled(request, id, client, jkt)
          when Tokens::EXCHANGE then exchange(request, id, jkt)
          else refused(400, "unsupported_grant_type")
          end
        end

        def grant(client_id, subject, scope, resource, **more)
          {
            "client_id" => client_id, "subject" => subject, "scope" => scope.to_s, "resource" => Array(resource),
            "sid" => "sid-#{SecureRandom.hex(8)}"
          }.merge(more)
        end

        def redeem(request, id, jkt)
          form = request[:body]
          held = @codes.delete(form["code"])

          return refused(400, "invalid_grant") if held.nil? || held["client_id"] != id
          return refused(400, "invalid_grant") unless held["redirect_uri"] == form["redirect_uri"]
          return refused(400, "invalid_grant") unless Proof.digest(form["code_verifier"].to_s) == held["challenge"]

          asked = resources(request)
          held = held.merge("resource" => asked) unless asked.empty?

          signed_in(held, id, jkt)
        end

        def refreshed(request, id, jkt)
          form = request[:body]
          held = @grants.delete(form["refresh_token"])

          return refused(400, "invalid_grant") if held.nil? || held["client_id"] != id

          held = held.merge("scope" => form["scope"]) if form["scope"]
          asked = resources(request)
          held = held.merge("resource" => asked) unless asked.empty?

          signed_in(held, id, jkt)
        end

        def polled(request, id, client, jkt)
          if @pending.positive?
            @pending -= 1

            return refused(400, "authorization_pending") if @slowed

            @slowed = true
            return refused(400, "slow_down")
          end

          signed_in(grant(id, "ada", request[:body]["scope"] || client.scope, resources(request)), id, jkt)
        end

        def signed_in(held, id, jkt)
          scopes = held["scope"].split
          subject = held["subject"]
          person = subject == id ? nil : person(subject)
          org = organization(person, held["organization"]) if person && scopes.include?("organization")
          aud = held["resource"].empty? ? audience : held["resource"]
          aud = aud.first if aud.is_a?(Array) && aud.size == 1
          access = access_token(subject: subject, scope: held["scope"], audience: aud, client_id: id,
                                cnf: jkt && { "jkt" => jkt }, org: org)
          refresh = SecureRandom.hex(16)
          @grants[refresh] = held

          body = {
            "access_token" => access,
            "token_type" => jkt ? Proof::SCHEME : "Bearer",
            "expires_in" => lifetime,
            "scope" => held["scope"],
            "refresh_token" => refresh
          }

          body["id_token"] = id_token(held, id, access, person, org) if person && scopes.include?("openid")

          delegated = scopes.filter_map { |scope| scope.delete_prefix("masks:delegate:") if scope.start_with?("masks:delegate:") }

          unless delegated.empty?
            body["delegations"] = delegated.map do |provider|
              { "connection" => "connection-#{provider}", "provider" => provider, "provider_name" => provider.capitalize,
                "subject" => "#{subject}@#{provider}.example" }
            end
          end

          [ 200, body ]
        end

        def organization(person, key)
          orgs = Array(person["orgs"])

          orgs.find { |org| org["key"] == key } || orgs.first
        end

        def id_token(held, id, access, person, org)
          now = Time.now.to_i
          claims = {
            "iss" => url,
            "sub" => held["subject"],
            "aud" => id,
            "exp" => now + 900,
            "iat" => now,
            "nonce" => held["nonce"],
            "sid" => held["sid"],
            "at_hash" => IdToken.half_hash(access),
            "auth_time" => auth_time,
            "org" => org
          }.merge(person.slice("name", "preferred_username", "email", "email_verified", "tenant", "masks:avatars"))

          sign(claims.compact)
        end

        def exchange(request, id, jkt)
          form = request[:body]
          @exchanges << form

          return refused(400, "invalid_request") if form["subject_token"].to_s.empty?

          if form["requested_token_type"] == UPSTREAM
            return [ 200, { "access_token" => "upstream-#{SecureRandom.hex(8)}", "issued_token_type" => UPSTREAM,
                            "token_type" => "Bearer", "expires_in" => 600, "scope" => form["scope"].to_s } ]
          end

          subject = decoded(form["subject_token"])

          return refused(400, "invalid_grant") if subject.nil?
          return refused(400, "invalid_grant") if subject.dig("cnf", "jkt") && subject.dig("cnf", "jkt") != jkt

          scope = form["scope"] || subject["scope"].to_s
          aud = resources(request)
          aud = subject["aud"] if aud.empty?
          aud = aud.first if aud.is_a?(Array) && aud.size == 1
          expires_in = [ form["requested_lifetime"].to_i.nonzero? || lifetime, lifetime ].min
          actor = form["actor_token"] && decoded(form["actor_token"])
          act = actor ? { "sub" => actor["sub"], "client_id" => actor["client_id"] } : { "sub" => id }
          access = access_token(subject: subject["sub"], scope: scope, audience: aud, expires_in: expires_in,
                                client_id: id, cnf: jkt && { "jkt" => jkt }, act: act)

          [ 200, { "access_token" => access, "issued_token_type" => Tokens::ACCESS_TOKEN,
                   "token_type" => jkt ? Proof::SCHEME : "Bearer", "expires_in" => expires_in, "scope" => scope } ]
        end

        def device(request)
          id, _, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed && request[:body]["client_id"] == id

          [ 200, { "device_code" => "device-#{SecureRandom.hex(8)}", "user_code" => "ABCD-EFGH",
                   "verification_uri" => "#{url}/device", "expires_in" => 600, "interval" => 0 } ]
        end

        def revoke(request)
          _, _, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed

          @revoked << request[:body]["token"].to_s

          [ 200, {} ]
        end

        def introspect(request)
          id, _, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed

          claims = decoded(request[:body]["token"])

          return [ 200, { "active" => false } ] if claims.nil?

          held = {
            "active" => true,
            "scope" => claims["scope"].to_s,
            "client_id" => claims["client_id"],
            "token_type" => claims.key?("cnf") ? Proof::SCHEME : "Bearer",
            "cnf" => claims["cnf"],
            "exp" => claims["exp"],
            "iat" => claims["iat"],
            "sub" => claims["sub"],
            "aud" => Array(claims["aud"]),
            "iss" => url,
            "jti" => claims["jti"],
            "tenant" => tenant,
            "asked_by" => id
          }
          held = held.merge(person(claims["sub"]).slice("preferred_username", "orgs"), "org" => claims["org"]) if @people.key?(claims["sub"])

          [ 200, held.compact ]
        end

        def userinfo(request)
          scheme, token = request[:headers]["authorization"].to_s.split(" ", 2)
          claims = decoded(token)

          return refused(401, "invalid_token") if claims.nil?

          bound = claims.dig("cnf", "jkt")

          return refused(401, "invalid_token") unless bound.nil? == (scheme.to_s.casecmp?("Bearer"))

          if bound
            jkt, proven = proof(request, "GET", "/userinfo", access_token: token)

            return refused(401, "invalid_dpop_proof") unless proven && jkt == bound
          end

          [ 200, person(claims["sub"]) ]
        end

        def avatar(request)
          return [ 401, nil ] if request[:headers]["authorization"].to_s.empty?

          [ 200, photo, { "Content-Type" => photo_type } ]
        end

        def register(request)
          presented = request[:headers]["authorization"].to_s.delete_prefix("Bearer ")
          id = @initial.delete(presented)

          return refused(401, "invalid_token") if id.nil?

          metadata = request[:body].is_a?(Hash) ? request[:body] : {}
          method = metadata["token_endpoint_auth_method"] || "client_secret_basic"
          secret = SecureRandom.hex(16) if method.start_with?("client_secret")
          token = SecureRandom.hex(16)

          @clients[id] = Registered.new(method: method, secret: secret, jwks: metadata["jwks"] || { "keys" => [] },
                                        scope: metadata["scope"], metadata: metadata)
          @registrations[id] = token
          uri = foreign_uri ? "https://elsewhere.example/register/#{id}" : "#{url}/register/#{id}"

          [ 201, metadata.merge("client_id" => id, "client_secret" => secret, "registration_access_token" => token,
                                "registration_client_uri" => uri).compact ]
        end

        def registration(request, id)
          held = @registrations[id]
          client = @clients[id]

          return refused(401, "invalid_token") if held.nil? || client.nil? || request[:headers]["authorization"] != "Bearer #{held}"

          case request[:method]
          when "DELETE"
            @registrations.delete(id)
            @clients.delete(id)
            [ 204, nil ]
          when "PUT"
            metadata = request[:body].is_a?(Hash) ? request[:body] : {}
            client.scope = metadata["scope"] || client.scope
            client.metadata = client.metadata.merge(metadata)
            [ 200, client.metadata.merge("client_id" => id) ]
          else
            [ 200, client.metadata.merge("client_id" => id, "token_endpoint_auth_method" => client.method, "scope" => client.scope).compact ]
          end
        end

        def enroll(request)
          id, _, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed

          form = request[:body]
          scope = form["scope"].to_s

          return refused(400, "invalid_request") if scope.empty?

          token = SecureRandom.hex(16)
          machine = "machine-#{SecureRandom.hex(6)}"
          @initial[token] = machine
          @enrolled[machine] = id

          [ 201, { "initial_access_token" => token, "expires_in" => (form["expires_in"] || 900).to_i, "scope" => scope } ]
        end

        def unenroll(request, machine)
          id, _, allowed = authenticated(request)

          return refused(401, "invalid_client") unless allowed
          return refused(404, "invalid_request") unless @enrolled[machine] == id

          @clients.delete(machine)
          @registrations.delete(machine)
          [ 204, nil ]
        end

        def end_session(query)
          asked = URI.decode_www_form(query.to_s).to_h
          target = asked["post_logout_redirect_uri"].to_s

          return [ 200, { "signed_out" => true } ] if target.empty?

          back = URI.parse(target)
          back.query = [ back.query, URI.encode_www_form([ [ "state", asked["state"] ] ].reject { |_, value| value.nil? }) ].compact.reject(&:empty?).join("&")

          [ 302, nil, { "Location" => back.to_s } ]
        end
    end
  end
end
