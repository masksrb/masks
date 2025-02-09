# frozen_string_literal: true
module Masks
  module Openid
    class DiscoveriesController < ApplicationController
      before_action :find_client

      def jwks
        jwks =
          JSON::JWK::Set.new(
            JSON::JWK.new(client.public_key, use: :sig, kid: client.kid),
          )

        render json: jwks
      end

      def new
        authorization_endpoint =
          if client.internal?
            main_app.masks_login_url(client)
          else
            main_app.masks_login_url
          end

        registration_endpoint =
          if client.allow_registration?
            main_app.masks_client_registration_url(client)
          end

        render json:
                 OpenIDConnect::Discovery::Provider::Config::Response.new(
                   issuer: client.issuer,
                   authorization_endpoint:,
                   registration_endpoint:,
                   token_endpoint: main_app.masks_token_endpoint_url,
                   userinfo_endpoint: main_app.masks_userinfo_url,
                   jwks_uri: main_app.masks_client_jwks_url(client),
                   scopes_supported: client.scopes,
                   response_types_supported: client.response_types,
                   grant_types_supported: client.grant_types,
                   claims_parameter_supported: false,
                   request_parameter_supported: false,
                   request_uri_parameter_supported: false,
                   subject_types_supported: client.subject_types,
                   id_token_signing_alg_values_supported: [:RS256],
                   token_endpoint_auth_methods_supported: %w[
                     client_secret_basic
                     client_secret_post
                   ],
                   claims_supported: %w[sub iss name email],
                 )
      end

      private

      def find_client
        head :not_found unless client
      end

      def client
        @client ||=
          begin
            client = Masks.clients.discover(params[:client_id])
            client if client&.allow_discovery?
          end
      end
    end
  end
end
