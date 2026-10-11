module Masks
  module Server
    module Manage
      module Types
        class InvitationOutcomeType < BaseObject
          description "What inviting one address did."

          field :email, String, null: false
          field :outcome, String, null: false,
                description: "invited, exists when an account already uses the address, or invalid when it is not an address."
          field :delivered, Boolean, null: false
          field :url, String, description: "The invitation link, when masks could not mail it."
          field :actor, ActorType
        end
      end
    end
  end
end
