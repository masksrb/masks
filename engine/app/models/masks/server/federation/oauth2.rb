module Masks
  module Server
    module Federation
      class OAuth2 < Protocol
        private

          def identify(tokens, _handoff, _params)
            raise Provider::Untrusted, "#{provider.name} returned no access token" if tokens["access_token"].blank?

            provider.get(provider.userinfo_url, tokens["access_token"])
          end

          def supplement(tokens)
            return {} if provider.emails_url.blank?

            listed = provider.get_list(provider.emails_url, tokens["access_token"])
            chosen = listed.find { |one| one["primary"] && one["verified"] == true } ||
              listed.find { |one| one["verified"] == true }

            chosen ? { "email" => chosen["email"].to_s, "email_verified" => true } : { "email" => nil, "email_verified" => nil }
          rescue Provider::Refused
            { "email" => nil, "email_verified" => nil }
          end
      end
    end
  end
end
