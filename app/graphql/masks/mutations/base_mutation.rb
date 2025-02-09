# frozen_string_literal: true

module Masks::Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    argument_class Masks::Types::BaseArgument
    field_class Masks::Types::BaseField
    input_object_class Masks::Types::BaseInputObject
    object_class Masks::Types::BaseObject

    def t(key)
      return unless key

      I18n.t(key)
    end
  end
end
