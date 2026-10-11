module Masks
  module Server
    module Manage
      module Mutations
        class RemoveTenantLogo < BaseMutation
          requires :owner

          field :tenant, Types::TenantType, null: false

          def resolve
            Masks::Server::TenantLogo.forget!(Current.tenant)

            { tenant: Current.tenant }
          end
        end
      end
    end
  end
end
