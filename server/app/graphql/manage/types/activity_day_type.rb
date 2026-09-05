module Manage
  module Types
    class ActivityDayType < BaseObject
      field :date, GraphQL::Types::ISO8601Date, null: false
      field :sign_ins, Integer, null: false
    end
  end
end
