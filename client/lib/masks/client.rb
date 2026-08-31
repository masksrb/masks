require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

require_relative "client/version"
require_relative "client/errors"
require_relative "client/http"
require_relative "client/pkce"
require_relative "client/issuer"
require_relative "client/registry"
require_relative "client/tokens"
require_relative "client/claims"
require_relative "client/introspection"
require_relative "client/session"
require_relative "client/verifier"
require_relative "client/resource"
require_relative "client/rack"
require_relative "client/registration"
require_relative "client/handshake"

module Masks
  module Client
    class << self
      def registry
        @registry ||= Registry.new
      end

      def issuer(url, **options)
        Issuer.resolve(url, **options)
      end

      def verifier(url, audience:, **options)
        Verifier.new(issuer(url), audience: audience, **options)
      end

      def resource(url, issuer:, **options)
        Resource.new(issuer: issuer, url: url, **options)
      end

      def handshake(url, **options)
        Handshake.new(url, **options)
      end
    end
  end
end
