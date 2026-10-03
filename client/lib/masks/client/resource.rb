module Masks
  module Client
    class Resource
      PRESENTED = /\A(Bearer|DPoP)[ \t]+([^\s,]+)[ \t]*\z/i.freeze
      METADATA_PATH = "/.well-known/oauth-protected-resource".freeze
      REQUIRED = %w[iss sub exp].freeze

      attr_reader :issuer, :url, :scopes

      def initialize(issuer:, url:, scopes: [], metadata_url: nil,
                     algorithms: Verifier::ALGORITHMS, required: REQUIRED, verifier: nil, replay: Proof.memory)
        @issuer = Issuer.resolve(issuer)
        @url = url.to_s
        @descriptions = describe(scopes)
        @scopes = (@descriptions.any? ? @descriptions.keys : Array(scopes).map(&:to_s)).freeze
        @metadata_url = metadata_url
        @required = Array(required)
        @verifier = verifier || Verifier.new(@issuer, audience: @url, algorithms: algorithms)
        @replay = replay
      end

      def authenticate(authorization, scope: nil, role: nil, organization: nil, proof: nil, method: nil, url: nil)
        scheme, token = presented!(authorization)
        held = @verifier.verify(token, required: @required, typ: Verifier::ACCESS_TOKEN)
        bound!(held, scheme, token, proof: proof, method: method, url: url)
        claims = Claims.new(held)

        Array(scope).each { |name| claims.permit!(name) }
        claims.member!(*Array(role), organization: organization) if role || organization

        claims
      rescue InvalidToken => e
        raise Unauthorized.new(e.message)
      end

      def token(authorization)
        authorization.to_s[PRESENTED, 2]
      end

      def metadata_url
        @metadata_url ||= "#{origin}#{METADATA_PATH}"
      end

      def metadata
        {
          "resource" => url,
          "authorization_servers" => [ issuer.url ],
          "scopes_supported" => scopes,
          "scope_descriptions" => @descriptions,
          "bearer_methods_supported" => [ "header" ],
          "dpop_signing_alg_values_supported" => Proof::ALGORITHMS
        }.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
      end

      def challenge(error = nil)
        error = Unauthorized.new(error.to_s) unless error.is_a?(Challenge)

        parameters = [
          [ "error", error.code ],
          [ "error_description", error.description ],
          [ "scope", error.scope || (scopes.join(" ") if scopes.any?) ],
          [ "resource_metadata", metadata_url ]
        ]

        scheme = error.dpop? ? "#{Proof::SCHEME} algs=\"#{Proof::ALGORITHMS.join(' ')}\", " : "Bearer "

        scheme + parameters.filter_map { |name, value|
          %(#{name}="#{quote(value)}") if value && !value.to_s.empty?
        }.join(", ")
      end

      private

        def describe(scopes)
          return {} unless scopes.is_a?(Hash)

          scopes.each_with_object({}) do |(scope, description), held|
            held[scope.to_s] = description.to_s
          end.freeze
        end

        def presented!(authorization)
          match = authorization.to_s.match(PRESENTED) || raise(Unauthenticated.new)

          [ match[1].casecmp?(Proof::SCHEME) ? :dpop : :bearer, match[2] ]
        end

        def bound!(claims, scheme, token, proof:, method:, url:)
          jkt = claims.dig("cnf", "jkt")

          raise Unauthorized.new("that token is not bound to a key, so it is presented as Bearer") if jkt.nil? && scheme == :dpop
          raise Unauthorized.new("that token is bound to a key, so it is presented as DPoP with a proof", dpop: true) if jkt && scheme != :dpop
          return if jkt.nil?

          Proof.new(proof, method: method, url: url || self.url, replay: @replay).check!(access_token: token, jkt: jkt)
        rescue Proof::Invalid => e
          raise Unauthorized.new(e.message, code: "invalid_dpop_proof", dpop: true)
        end

        def origin
          uri = URI.parse(url)
          port = ":#{uri.port}" unless uri.port.nil? || uri.default_port == uri.port

          "#{uri.scheme}://#{uri.host}#{port}"
        rescue URI::InvalidURIError
          url
        end

        def quote(value)
          value.to_s.gsub(/[\\"]/, " ").gsub(/[[:cntrl:]]/, " ").strip
        end
    end
  end
end
