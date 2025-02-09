# frozen_string_literal: true

module Masks::Types
  class AdapterInputType < BaseInputObject
    argument :key, String, required: false
    argument :name, String, required: false
    argument :type, String, required: false
    argument :config, CamelizedJson, required: false
    argument :deleted, Boolean, required: false
  end
end
