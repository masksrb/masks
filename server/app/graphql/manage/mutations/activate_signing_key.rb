module Manage
  module Mutations
    class ActivateSigningKey < BaseMutation
      argument :kid, ID

      field :signing_key, Types::SigningKeyType, null: false

      def resolve(kid:)
        key = signing_key!(kid)

        refuse!("that key is already signing") if key.active?
        refuse!("a retired key cannot be activated") unless key.staged?

        audit!(::Event::SIGNING_KEY_ACTIVATED, kid: key.kid)

        { signing_key: key.activate! }
      end
    end
  end
end
