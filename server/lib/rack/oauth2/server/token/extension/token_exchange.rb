require "rack/oauth2"

module Rack
  module OAuth2
    module Server
      class Token
        module Extension
          class TokenExchange < Abstract::Handler
            GRANT_TYPE_URN = "urn:ietf:params:oauth:grant-type:token-exchange".freeze

            class << self
              def grant_type_for?(grant_type)
                grant_type == GRANT_TYPE_URN
              end
            end

            def _call(env)
              @request = Request.new(env)
              @response = Response.new(request)
              super
            end

            class Request < Token::Request
              attr_required :subject_token
              attr_optional :subject_token_type, :requested_token_type, :scope,
                            :actor_token, :actor_token_type, :requested_lifetime

              def initialize(env)
                super

                @grant_type = GRANT_TYPE_URN
                @subject_token = params["subject_token"]
                @subject_token_type = params["subject_token_type"]
                @requested_token_type = params["requested_token_type"]
                @scope = params["scope"]
                @actor_token = params["actor_token"]
                @actor_token_type = params["actor_token_type"]
                @requested_lifetime = params["requested_lifetime"]

                attr_missing!
              end
            end
          end
        end
      end
    end
  end
end
