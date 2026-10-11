module Masks
  module Server
    module Manage
      module Types
        class AppSettingType < BaseObject
          description "One value to enter in the app, under the label the app uses for it."

          field :label, String, null: false
          field :value, String, null: false
        end
      end
    end
  end
end
