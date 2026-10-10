module Masks
  module Server
    module Manage
      module Mutations
        class ResetSecondFactors < BaseMutation
          requires :support

          argument :uuid, ID

          field :actor, Types::ActorType, null: false

          def resolve(uuid:)
            actor = actor!(uuid)

            Masks::Server::HelpRequests.reset!(actor, by: viewer)

            { actor: actor.reload }
          end
        end
      end
    end
  end
end
