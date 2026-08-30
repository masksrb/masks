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
require_relative "client/tokens"
require_relative "client/session"
require_relative "client/verifier"
require_relative "client/registration"

module Masks
  module Client
    class << self
      def issuer(url, **options)
        Issuer.new(url, **options)
      end

      def verifier(url, audience:, **options)
        Verifier.new(Issuer.new(url, **options), audience: audience)
      end
    end
  end
end
