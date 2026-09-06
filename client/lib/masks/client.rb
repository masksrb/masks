require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

require_relative "version"
require_relative "client/errors"
require_relative "client/http"
require_relative "client/pkce"
require_relative "client/stores"
require_relative "client/tracker"
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
  # = Masks::Client
  #
  # The protocol half of the gem: plain Ruby, no \Rails, no database. Every
  # entry point here is a class method that builds one of the objects below.
  #
  # Which one you want depends on what the application is doing:
  #
  # [issuer]    an app signing people in — discovery, PKCE, the code exchange
  # [verifier]  an API checking a bearer it was handed
  # [resource]  an API publishing what it is and which scopes it takes
  # [handshake] an app registering itself, once, without a copied secret
  #
  # Everything reachable from here talks HTTP to a masks issuer and holds no
  # state of its own beyond the discovery cache in ::registry.
  module Client
    class << self
      # The process-wide cache of resolved issuers, so discovery is fetched
      # once rather than per request.
      #
      # @return [Masks::Client::Registry]
      def registry
        @registry ||= Registry.new
      end

      # Resolves +url+ through its discovery document and returns the issuer
      # it describes. Cached in ::registry, so calling this per request is
      # cheap after the first.
      #
      #   issuer = Masks::Client.issuer("https://auth.example")
      #   issuer.authorization_url(client_id: id, redirect_uri: uri)
      #
      # @return [Masks::Client::Issuer]
      def issuer(url, **options)
        Issuer.resolve(url, **options)
      end

      # Checks tokens minted by the issuer at +url+ against +audience+ — the
      # API's own URL, which the token names in +aud+. A token issued for
      # anything else is refused rather than merely noted.
      #
      # @return [Masks::Client::Verifier]
      def verifier(url, audience:, **options)
        Verifier.new(issuer(url), audience: audience, **options)
      end

      # Describes this API to callers: the scopes it accepts and the issuer
      # that may mint tokens for it, served as RFC 9728 metadata.
      #
      # @return [Masks::Client::Resource]
      def resource(url, issuer:, **options)
        Resource.new(issuer: issuer, url: url, **options)
      end

      # Registers this application against a masks issuer. A person approves
      # it in their browser and the credentials come back server to server, so
      # no secret is pasted between the two.
      #
      # @return [Masks::Client::Handshake]
      def handshake(url, **options)
        Handshake.new(url, **options)
      end
    end
  end
end
