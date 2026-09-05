module Manage
  module Mutations
    class RotateSigningKey < BaseMutation
      field :signing_key, Types::SigningKeyType, null: false

      def resolve
        { signing_key: ::SigningKey.rotate!(tenant: Current.tenant) }
      end
    end
  end
end
