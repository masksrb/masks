module Masks
  module Server
    module Manage
      module Mutations
        class DeclineAccess < BaseMutation
          requires :security

          description "Declines a waiting access request. The actor is told by email and can ask again in an hour."

          argument :id, ID

          field :access_request, Types::AccessRequestType, null: false

          def resolve(id:)
            asked = access_request!(id)

            asked.decline!(by: viewer, journey: Masks::Server::Journey.manage(viewer))

            { access_request: asked }
          rescue Masks::Server::AccessRequest::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
