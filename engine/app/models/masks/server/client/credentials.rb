module Masks
  module Server
    class Client
      module Credentials
        extend ActiveSupport::Concern

        included do
          attr_reader :secret, :registration_token

          validate :keys_are_usable
          validate :client_credentials_are_confidential
        end

        class_methods do
          def by_registration_token(token)
            return nil if token.blank?

            active.find_by(registration_token_digest: Digest::SHA256.hexdigest(token.to_s))
          end
        end

        def public?
          token_endpoint_auth_method == "none"
        end

        def asserts?
          token_endpoint_auth_method == PRIVATE_KEY_JWT
        end

        def secret?
          SECRET_AUTH_METHODS.include?(token_endpoint_auth_method)
        end

        def keys?
          jwks.present? || jwks_uri.present?
        end

        def issue_credentials!
          issue_secret! if secret?
          issue_registration_token!
          save!
          self
        end

        def issue_secret!
          @secret = SecureRandom.urlsafe_base64(48)
          self.secret_digest = BCrypt::Password.create(@secret)
          @secret
        end

        def issue_registration_token!
          @registration_token = SecureRandom.urlsafe_base64(48)
          self.registration_token_digest = Digest::SHA256.hexdigest(@registration_token)
          @registration_token
        end

        def authenticate_secret(candidate)
          return true if public?

          secret_matches?(candidate) && !secret_expired?
        end

        def secret_matches?(candidate)
          return false unless secret?
          return false if secret_digest.blank? || candidate.blank?

          BCrypt::Password.new(secret_digest) == candidate.to_s
        rescue BCrypt::Errors::InvalidHash
          false
        end

        def secret_expired?
          secret_expires_at.present? && secret_expires_at.past?
        end

        private

          def client_credentials_are_confidential
            return unless grants?(CLIENT_CREDENTIALS)

            errors.add(:grant_types, "client_credentials needs a client that authenticates, not a public one") if public?
            errors.add(:grant_types, "client_credentials may only be granted to an approved client") unless approved?
          end

          def keys_are_usable
            errors.add(:jwks, "and jwks_uri cannot both be registered") if jwks.present? && jwks_uri.present?

            if require_signed_request_object? && !keys?
              errors.add(:require_signed_request_object, "needs jwks or a jwks_uri to check request objects against")
            end

            if asserts? && !keys?
              errors.add(:token_endpoint_auth_method, "private_key_jwt needs jwks or a jwks_uri to check assertions against")
            end

            self.jwks = ClientKeys.check!(jwks) if jwks.present? && will_save_change_to_jwks?
            ClientKeys.fetch(jwks_uri) if jwks_uri.present? && will_save_change_to_jwks_uri?
          rescue ClientKeys::Refused => e
            errors.add(jwks_uri.present? && jwks.blank? ? :jwks_uri : :jwks, e.message)
          end
      end
    end
  end
end
