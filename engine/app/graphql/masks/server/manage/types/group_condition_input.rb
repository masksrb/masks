module Masks
  module Server
    module Manage
      module Types
        class GroupConditionInput < GraphQL::Schema::InputObject
          description "One condition of a group's rule."

          argument :kind, String, description: "email_domain or profile."
          argument :field, String, required: false,
                   description: "For profile: name, given_name, family_name, middle_name, nickname, gender, zoneinfo, or locale."
          argument :value, String, description: "The domain a verified email address ends with, or the value the profile field equals."
        end
      end
    end
  end
end
