module Masks
  module Server
    module Manage
      module Mutations
        class StageSigningKey < BaseMutation
          field :signing_key, Types::SigningKeyType, null: false

          def resolve
            tenant = Current.tenant

            if Masks::Server::SigningKey.staged.exists?
              refuse!("a key is already staged — activate or discard it before staging another")
            end

            key = Masks::Server::SigningKey.stage!(tenant: tenant)

            audit!(Masks::Server::Event::SIGNING_KEY_STAGED, kid: key.kid)

            { signing_key: key }
          end
        end
      end
    end
  end
end
