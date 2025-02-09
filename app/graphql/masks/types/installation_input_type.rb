# frozen_string_literal: true

module Masks::Types
  class InstallationInputType < BaseInputObject
    argument :theme, CamelizedJson, required: false
    argument :nicknames, CamelizedJson, required: false
    argument :passwords, CamelizedJson, required: false
    argument :backup_codes, CamelizedJson, required: false
    argument :clients, CamelizedJson, required: false
    argument :actors, CamelizedJson, required: false
    argument :devices, CamelizedJson, required: false
    argument :sessions, CamelizedJson, required: false
  end
end
