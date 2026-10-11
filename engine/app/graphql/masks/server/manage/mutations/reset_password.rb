module Masks
  module Server
    module Manage
      module Mutations
        class ResetPassword < BaseMutation
          requires :support

          argument :uuid, ID

          field :actor, Types::ActorType, null: false
          field :delivered, Boolean, null: false
          field :url, String

          def resolve(uuid:)
            actor = actor!(uuid)

            refuse!("#{actor.identifier} has not accepted an invitation yet") unless actor.activated?
            needs!(:security, "handing over a reset link masks cannot mail") unless Recoveries.mailable?(actor)

            Recoveries.open(actor: actor, journey: Masks::Server::Journey.manage(viewer)).merge(actor: actor)
          end
        end
      end
    end
  end
end
