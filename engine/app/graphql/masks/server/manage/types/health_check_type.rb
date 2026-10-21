module Masks
  module Server
    module Manage
      module Types
        class HealthCheckType < BaseObject
          description "The latest result of one health check. Checks run every 10 minutes."

          field :name, ID, null: false, description: "jobs, worker, queue, ldap, metrics, mail, origin, domains, or keys."
          field :status, String, null: false, description: "ok, warning, or failing."
          field :summary, String, null: false, description: "A short word for what the check found, such as none, stale, or silent."
          field :details, GraphQL::Types::JSON, null: false, description: "The figures and names behind the summary."
          field :checked_at, GraphQL::Types::ISO8601DateTime, null: false
          field :changed_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the status last changed."
        end
      end
    end
  end
end
