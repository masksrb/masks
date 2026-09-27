module Masks
  module Server
    module Manage
      module Mutations
        class ResendOrganizationInvitation < OrganizationMutation
          requires :support

          description "Sends an organization invitation again and starts its lifetime over. " \
                      "An invitation is sent again at most once an hour."

          argument :organization, ID
          argument :uuid, ID

          field :membership, Types::MembershipType, null: false
          field :delivered, Boolean, null: false
          field :url, String

          def resolve(organization:, uuid:)
            held = live!(organization!(organization))
            membership = member!(held, actor!(uuid))

            Masks::Server::Members.resend!(membership, by: viewer, journey: Masks::Server::Journey.manage(viewer),
                                                       manager: true)
          rescue Masks::Server::Members::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
