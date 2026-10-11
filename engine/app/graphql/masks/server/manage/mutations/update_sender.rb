module Masks
  module Server
    module Manage
      module Mutations
        class UpdateSender < BaseMutation
          requires :security

          argument :key, ID
          argument :name, String, required: false
          argument :config, GraphQL::Types::JSON, required: false
          argument :primary, Boolean, required: false

          field :sender, Types::SenderType, null: false

          def resolve(key:, name: nil, config: nil, primary: nil)
            sender = sender!(key)

            refuse!("#{sender.name} is archived; restore it first") if sender.archived?

            sender.name = name unless name.nil?
            sender.configure(config) unless config.nil?
            sender.primary = primary unless primary.nil?

            save!(sender)

            audit!(Masks::Server::Event::SENDER_UPDATED, sender: sender.key, service: sender.service,
                                             changed: Array(config&.keys) + [ name && "name", primary.nil? ? nil : "primary" ].compact)

            { sender: sender }
          end
        end
      end
    end
  end
end
