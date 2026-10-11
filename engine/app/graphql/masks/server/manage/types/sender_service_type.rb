module Masks
  module Server
    module Manage
      module Types
        class SenderServiceType < BaseObject
          field :service, ID, null: false
          field :kind, String, null: false
          field :label, String, null: false
          field :fields, [ SenderFieldType ], null: false
        end
      end
    end
  end
end
