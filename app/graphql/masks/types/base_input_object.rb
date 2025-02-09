# frozen_string_literal: true

module Masks::Types
  class BaseInputObject < GraphQL::Schema::InputObject
    argument_class BaseArgument
  end
end
