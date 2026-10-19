module Masks
  module Server
    module Manage
      module Mutations
        class UnenrollClient < BaseMutation
          requires :security

          argument :client_id, ID

          field :client, Types::ClientType, null: false

          def resolve(client_id:)
            machine = client!(client_id)

            refuse!("that client is not a machine an app enrolled, so archive it instead") unless machine.enrolled?

            revoked = machine.unenroll!

            audit!(Masks::Server::Event::CLIENT_UNENROLLED, client: machine, name: machine.name,
                                                             enrolled_by: machine.enrolled_by.client_id, revoked: revoked)

            { client: machine }
          end
        end
      end
    end
  end
end
