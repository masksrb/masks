module Masks
  module Server
    module Manage
      module Mutations
        class TestSender < BaseMutation
          requires :security

          argument :key, ID
          argument :to, String

          field :delivered, Boolean, null: false
          field :failure, String

          def resolve(key:, to:)
            sender = sender!(key)

            sender.deliver_test(to, journey: Masks::Server::Journey.manage(viewer))

            audit!(Masks::Server::Event::SENDER_TESTED, sender: sender.key, service: sender.service, delivered: true)

            { delivered: true, failure: nil }
          rescue Masks::Server::Sender::Failed => failure
            audit!(Masks::Server::Event::SENDER_TESTED, sender: sender.key, service: sender.service, delivered: false)

            { delivered: false, failure: failure.message }
          end
        end
      end
    end
  end
end
