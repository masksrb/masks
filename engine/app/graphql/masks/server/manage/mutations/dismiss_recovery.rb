module Masks
  module Server
    module Manage
      module Mutations
        class DismissRecovery < BaseMutation
          requires :support

          argument :uuid, ID

          field :actor, Types::ActorType, null: false

          def resolve(uuid:)
            actor = actor!(uuid)

            refuse!("#{actor.identifier} has not asked for help") if actor.recovery_requested_at.nil?

            Masks::Server::HelpRequests.dismiss!(actor, by: viewer)

            { actor: actor }
          end
        end
      end
    end
  end
end
