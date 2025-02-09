require "test_helper"

module Auth
  module Shared
    module SingleSignOn
      extend ActiveSupport::Concern

      included do
        [
          {
            type: Masks::Providers::Github,
            common: true,
            client_id: "test123",
            client_secret: "456789",
            redirect_uri: "github.com/login/oauth/authorize?client_id=test123",
          },
          {
            type: Masks::Providers::Facebook,
            common: true,
            client_id: "test123",
            client_secret: "456789",
          },
          {
            type: Masks::Providers::Twitter,
            common: true,
            client_id: "test123",
            client_secret: "456789",
          },
          {
            skip: true, # I don't want to pay to test this
            type: Masks::Providers::Apple,
            common: true,
            client_id: "test123",
            client_secret: "456789",
          },
          {
            type: Masks::Providers::Google,
            common: true,
            client_id: "test123",
            client_secret: "456789",
          },
        ].each do |opts|
          describe "SSO #{opts[:type]}" do
            before do
              OmniAuth.config.logger.level = Logger::INFO
              OmniAuth.config.test_mode = false

              @redirect_uri = opts.delete(:redirect_uri)
              @provider = Masks::Provider.create!(**opts.except(:skip, :before))
            end

            test "SSO requests can be disabled" do
              client.update!(allow_sso: false)

              enter
              event "sso:request",
                    updates: {
                      provider: @provider.key,
                      origin: Masks.url,
                    }

              assert_not entry_json.dig("extras", "redirect")
            end

            test "SSO callbacks fail when no SSO request is available" do
              get "/sso/#{@provider.key}"

              assert_equal 400, status
            end

            test "SSO requests store state under the device" do
              skip if opts[:skip]

              enter
              event "sso:request",
                    updates: {
                      provider: @provider.key,
                      origin: Masks.url,
                    }

              assert redirect = entry_json.dig("extras", "redirect")

              assert_includes redirect, @redirect_uri if @redirect_uri
              assert_equal 1, masks_session.sso_request.count

              assert_match @provider.key, masks_session.sso_request.tracked
              assert_equal entry_id, masks_session.sso_request.data["entry"]
              assert_equal Masks.url, masks_session.sso_request.data["origin"]
              assert_not_empty masks_session.sso_request.data["session"]
            end

            test "SSO callback augments session data (and removes the original request)" do
              skip if opts[:skip]

              enter
              event "sso:request",
                    updates: {
                      provider: @provider.key,
                      origin: Masks.url,
                    }

              auth_hash = { uid: SecureRandom.uuid }.stringify_keys

              mock_omniauth(auth_hash)

              get "/sso/#{@provider.key}"

              assert masks_session.sso_request.with(@provider).data["attempted"]
              assert_equal @provider.key,
                           masks_session[:single_sign_on]["provider"]
              assert_equal auth_hash, masks_session[:single_sign_on]["omniauth"]
              assert_not masks_session[:single_sign_on]["accepted"]
            end

            test "SSO callbacks are not re-attempted" do
              skip if opts[:skip]

              enter
              event "sso:request",
                    updates: {
                      provider: @provider.key,
                      origin: Masks.url,
                    }

              auth_hash = { uid: SecureRandom.uuid }.stringify_keys

              mock_omniauth(auth_hash)

              get "/sso/#{@provider.key}"

              OmniAuth.config.test_mode = false
              OmniAuth.config.mock_auth = {}

              get "/sso/#{@provider.key}"
            end

            private

            def mock_omniauth(hash)
              OmniAuth.config.test_mode = true
              OmniAuth.config.mock_auth[:default] = OmniAuth::AuthHash.new(hash)
            end
          end
        end
      end
    end
  end
end
