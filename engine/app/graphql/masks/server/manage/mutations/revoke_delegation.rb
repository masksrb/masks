module Masks
  module Server
    module Manage
      module Mutations
        class RevokeDelegation < BaseMutation
          argument :id, ID

          field :delegation, Types::DelegationType, null: false

          def resolve(id:)
            delegation = Masks::Server::Delegation.find_by(uuid: id) || refuse!("no delegation with that id")

            delegation.revoke!(reason: "revoked by #{viewer.identifier}", by: viewer)

            { delegation: delegation }
          end
        end
      end
    end
  end
end
