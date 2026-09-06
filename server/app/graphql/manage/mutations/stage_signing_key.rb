module Manage
  module Mutations
    class StageSigningKey < BaseMutation
      field :signing_key, Types::SigningKeyType, null: false

      def resolve
        tenant = Current.tenant

        if ::SigningKey.staged.exists?
          refuse!("a key is already staged — activate or discard it before staging another")
        end

        key = ::SigningKey.stage!(tenant: tenant)

        audit!(::Event::SIGNING_KEY_STAGED, kid: key.kid)

        { signing_key: key }
      end
    end
  end
end
