module Masks
  module Server
    module Manage
      module Mutations
        class UploadTenantLogo < BaseMutation
          requires :owner

          argument :logo, Types::UploadType

          field :tenant, Types::TenantType, null: false

          def resolve(logo:)
            Masks::Server::TenantLogo.store!(Current.tenant, logo)

            { tenant: Current.tenant }
          rescue Pictures::Unreadable => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
