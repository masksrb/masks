module Masks
  module Server
    module Manage
      module Mutations
        class RotateSigningKey < BaseMutation
          field :signing_key, Types::SigningKeyType, null: false

          def resolve
            key = Masks::Server::SigningKey.rotate!(tenant: Current.tenant)

            audit!(Masks::Server::Event::SIGNING_KEY_ROTATED, kid: key.kid)

            { signing_key: key }
          end
        end
      end
    end
  end
end
