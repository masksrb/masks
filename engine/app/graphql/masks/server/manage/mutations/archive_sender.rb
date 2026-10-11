module Masks
  module Server
    module Manage
      module Mutations
        class ArchiveSender < BaseMutation
          requires :security

          argument :key, ID

          field :sender, Types::SenderType, null: false

          def resolve(key:)
            sender = sender!(key)

            refuse!("#{sender.name} is already archived") if sender.archived?

            sender.assign_attributes(archived_at: Time.current, primary: false)
            save!(sender)

            audit!(Masks::Server::Event::SENDER_ARCHIVED, sender: sender.key, service: sender.service)

            { sender: sender }
          end
        end
      end
    end
  end
end
