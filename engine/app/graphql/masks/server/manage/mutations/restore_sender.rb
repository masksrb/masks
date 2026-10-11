module Masks
  module Server
    module Manage
      module Mutations
        class RestoreSender < BaseMutation
          requires :security

          argument :key, ID

          field :sender, Types::SenderType, null: false

          def resolve(key:)
            sender = sender!(key)

            refuse!("#{sender.name} is not archived") unless sender.archived?

            sender.archived_at = nil
            save!(sender)

            audit!(Masks::Server::Event::SENDER_UPDATED, sender: sender.key, service: sender.service, changed: [ "restored" ])

            { sender: sender }
          end
        end
      end
    end
  end
end
