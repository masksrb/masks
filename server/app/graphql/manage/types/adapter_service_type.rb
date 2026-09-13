module Manage
  module Types
    class AdapterServiceType < BaseObject
      field :service, ID, null: false
      field :kind, String, null: false
      field :label, String, null: false
      field :fields, [ AdapterFieldType ], null: false
    end
  end
end
