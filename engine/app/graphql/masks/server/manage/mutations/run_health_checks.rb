module Masks
  module Server
    module Manage
      module Mutations
        class RunHealthChecks < BaseMutation
          requires :support

          description "Runs every health check now, instead of waiting for the next scheduled run."

          field :health, [ Types::HealthCheckType ], null: false

          def resolve
            { health: Masks::Server::Health.check!.sort_by(&:name) }
          end
        end
      end
    end
  end
end
