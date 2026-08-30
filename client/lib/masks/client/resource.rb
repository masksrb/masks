module Masks
  module Client
    class Resource
      BEARER = /\ABearer[ \t]+([^\s,]+)[ \t]*\z/i.freeze
      METADATA_PATH = "/.well-known/oauth-protected-resource".freeze
      REQUIRED = %w[iss sub exp].freeze

      attr_reader :issuer, :url, :scopes

      def initialize(issuer:, url:, scopes: [], metadata_url: nil,
                     algorithms: Verifier::ALGORITHMS, required: REQUIRED, verifier: nil)
        @issuer = Issuer.resolve(issuer)
        @url = url.to_s
        @descriptions = describe(scopes)
        @scopes = (@descriptions.any? ? @descriptions.keys : Array(scopes).map(&:to_s)).freeze
        @metadata_url = metadata_url
        @required = Array(required)
        @verifier = verifier || Verifier.new(@issuer, audience: @url, algorithms: algorithms)
      end

      def authenticate(authorization, scope: nil)
        claims = Claims.new(@verifier.verify(token!(authorization), required: @required))

        Array(scope).each { |name| claims.permit!(name) }

        claims
      rescue InvalidToken => e
        raise Unauthorized.new(e.message)
      end

      def token(authorization)
        authorization.to_s[BEARER, 1]
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
          "bearer_methods_supported" => [ "header" ]
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

        "Bearer " + parameters.filter_map { |name, value|
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

        def token!(authorization)
          token(authorization) || raise(Unauthenticated.new)
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
