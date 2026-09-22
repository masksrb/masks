module Masks
  module Server
    module Manage
      module Types
        class EventActionType < BaseObject
          field :action, String, null: false
          field :label, String, null: false

          def action
            object
          end

          def label
            I18n.t("events.actions.#{object}", default: object)
          end
        end
      end
    end
  end
end
