module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Status
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :health, [ HealthCheckType ], null: false,
                    description: "The latest result of each health check for this tenant and the server it runs on. " \
                                 "Empty until the first scheduled run."
              field :release, ReleaseType,
                    description: "The newest release when it is newer than this server. Null while the server is current, " \
                                 "or while MASKS_RELEASE_CHECK is off."
            end

            def health
              Masks::Server::HealthCheck.by_name
            end

            def release
              found = Masks::Server::Release.available

              return nil if found.nil?

              {
                version: found["version"],
                url: found["url"],
                operator_step: found["operator_step"] == true,
                checked_at: Time.iso8601(found["checked_at"])
              }
            end
          end
        end
      end
    end
  end
end
