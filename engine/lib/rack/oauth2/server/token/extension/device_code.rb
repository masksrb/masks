require "rack/oauth2"

module Rack
  module OAuth2
    module Server
      class Token
        module Extension
          class DeviceCode < Abstract::Handler
            GRANT_TYPE_URN = "urn:ietf:params:oauth:grant-type:device_code".freeze

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
              attr_required :device_code

              def initialize(env)
                super

                @grant_type = GRANT_TYPE_URN
                @device_code = params["device_code"]

                attr_missing!
              end
            end
          end
        end
      end
    end
  end
end
