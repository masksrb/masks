module Masks
  module Server
    module Manage
      module Types
        class TallyType < BaseObject
          field :actors, Integer, null: false
          field :clients, Integer, null: false
          field :sessions, Integer, null: false
          field :devices, Integer, null: false
          field :organizations, Integer, null: false, description: "Organizations that are not archived."
        end
      end
    end
  end
end
