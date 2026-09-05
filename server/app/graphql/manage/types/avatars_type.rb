module Manage
  module Types
    class AvatarsType < BaseObject
      field :photo, String
      field :identicon, String, null: false
      field :initials, String, null: false
    end
  end
end
