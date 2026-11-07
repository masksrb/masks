module Masks
  module Server
    module Federation
      class Mcp < Protocol
        private

          def identify(tokens, _handoff, _params)
            raise Provider::Untrusted, "#{provider.name} returned no access token" if tokens["access_token"].blank?

            return tokens if provider.userinfo_url.blank?

            tokens.merge(provider.get(provider.userinfo_url, tokens["access_token"]))
          end

          def anonymous?
            true
          end

          def scopes
            provider.scope_list
          end

          def delegation_extra
            super.merge("resource" => provider.resource_url)
          end
      end
    end
  end
end
