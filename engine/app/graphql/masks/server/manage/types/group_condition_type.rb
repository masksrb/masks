module Masks
  module Server
    module Manage
      module Types
        class GroupConditionType < BaseObject
          description "One condition of a group's rule. Every condition must hold for a person to be in the group."

          field :kind, String, null: false, description: "email_domain or profile."
          field :field, String, description: "The profile field a profile condition reads."
          field :value, String, null: false,
                description: "The domain a verified email address ends with, or the value the profile field equals. " \
                             "A profile condition matches only people whose profile a directory sets."

          def kind
            object["kind"]
          end

          def field
            object["field"]
          end

          def value
            object["value"]
          end
        end
      end
    end
  end
end
