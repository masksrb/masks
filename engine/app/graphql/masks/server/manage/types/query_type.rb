module Masks
  module Server
    module Manage
      module Types
        class QueryType < BaseObject
          LIMIT = 50
          CEILING = 200

          field :viewer, ActorType, null: false
          field :manage_levels, [ String ], null: false,
                                            description: "What the viewer's token may do here: read, support, security, and owner."
          field :tenant, TenantType, null: false

          include Actors
          include Clients
          include Providers
          include Organizations
          include Messaging
          include Activity
          include Status
          include Directory

          def viewer
            context[:actor]
          end

          def manage_levels
            ManageRoles.levels(context[:roles]).map(&:to_s)
          end

          def tenant
            Current.tenant
          end

          private

            def bounded(limit)
              [ limit || LIMIT, CEILING ].min
            end
        end
      end
    end
  end
end
