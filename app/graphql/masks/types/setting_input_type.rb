# frozen_string_literal: true

module Masks::Types
  class SettingInputType < BaseInputObject
    argument :settings, GraphQL::Types::JSON, required: false
  end
end
