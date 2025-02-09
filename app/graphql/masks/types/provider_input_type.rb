# frozen_string_literal: true

module Masks::Types
  class ProviderInputType < BaseInputObject
    argument :id, String, required: false

    Masks::Provider.settings.each do |key, conf|
      argument key, conf[:graphql], required: false
    end

    argument :settings, CamelizedJson, required: false
  end
end
