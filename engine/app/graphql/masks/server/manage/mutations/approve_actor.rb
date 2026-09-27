module Masks
  module Server
    module Manage
      module Mutations
        class ApproveActor < BaseMutation
          requires :support

          argument :uuid, ID

          field :actor, Types::ActorType, null: false

          def resolve(uuid:)
            actor = actor!(uuid)

            refuse!("#{actor.identifier} is not waiting for approval") if actor.pending_approval_at.nil?

            Masks::Server::Confirmations.approve!(actor, journey: Masks::Server::Journey.manage(viewer))

            { actor: actor }
          end
        end
      end
    end
  end
end
