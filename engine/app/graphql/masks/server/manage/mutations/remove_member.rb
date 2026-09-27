module Masks
  module Server
    module Manage
      module Mutations
        class RemoveMember < OrganizationMutation
          requires :support

          argument :organization, ID
          argument :uuid, ID

          field :organization, Types::OrganizationType, null: false

          def resolve(organization:, uuid:)
            held = organization!(organization)
            actor = actor!(uuid)
            Masks::Server::Members.remove!(member!(held, actor), by: viewer)

            { organization: held }
          rescue Masks::Server::Members::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
