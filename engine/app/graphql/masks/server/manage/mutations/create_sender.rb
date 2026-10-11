module Masks
  module Server
    module Manage
      module Mutations
        class CreateSender < BaseMutation
          requires :security

          argument :key, ID
          argument :service, String
          argument :name, String
          argument :config, GraphQL::Types::JSON, required: false
          argument :primary, Boolean, required: false

          field :sender, Types::SenderType, null: false

          def resolve(key:, service:, name:, config: nil, primary: nil)
            klass = Masks::Server::Sender.service_for(service) || refuse!("there is no sender for #{service}")

            refuse!("an sender is already keyed #{key}") if Masks::Server::Sender.exists?(key: key)

            sender = klass.new(key: key, name: name)
            sender.configure(config)
            sender.primary = primary.nil? ? Masks::Server::Sender.primary(klass.kind).nil? : primary

            save!(sender)

            audit!(Masks::Server::Event::SENDER_CREATED, sender: sender.key, service: sender.service)

            { sender: sender }
          end
        end
      end
    end
  end
end
