module Masks
  module Server
    module Manage
      module Mutations
        class GrantAccess < BaseMutation
          requires :security

          description "Grants a waiting access request by putting the actor in one of the groups the client allows. " \
                      "Name the group with label, or leave it out for the first one the client allows."

          argument :id, ID
          argument :label, String, required: false

          field :access_request, Types::AccessRequestType, null: false

          def resolve(id:, label: nil)
            asked = access_request!(id)

            asked.grant!(label: label, by: viewer, journey: Masks::Server::Journey.manage(viewer))

            { access_request: asked }
          rescue Masks::Server::AccessRequest::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
