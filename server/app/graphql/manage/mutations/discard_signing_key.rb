module Manage
  module Mutations
    class DiscardSigningKey < BaseMutation
      argument :kid, ID

      field :kid, ID, null: false

      def resolve(kid:)
        key = signing_key!(kid)

        refuse!("only a staged key may be discarded") unless key.staged?

        key.destroy!
        audit!(::Event::SIGNING_KEY_DISCARDED, kid: kid)

        { kid: kid }
      end
    end
  end
end
