module Masks
  module Server
    module Manage
      module Types
        class AdapterFieldType < BaseObject
          field :key, String, null: false
          field :label, String, null: false
          field :type, String, null: false
          field :secret, Boolean, null: false
          field :required, Boolean, null: false
          field :options, [ String ]
          field :default, GraphQL::Types::JSON
          field :hint, String
        end
      end
    end
  end
end
