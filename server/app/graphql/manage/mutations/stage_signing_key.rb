module Manage
  module Mutations
    class StageSigningKey < BaseMutation
      field :signing_key, Types::SigningKeyType, null: false

      def resolve
        tenant = Current.tenant

        if ::SigningKey.staged.exists?
          refuse!("a key is already staged — activate or discard it before staging another")
        end

        { signing_key: ::SigningKey.stage!(tenant: tenant) }
      end
    end
  end
end
