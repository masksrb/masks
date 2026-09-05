module Manage
  module Types
    class TallyType < BaseObject
      field :actors, Integer, null: false
      field :clients, Integer, null: false
      field :sessions, Integer, null: false
      field :devices, Integer, null: false
    end
  end
end
