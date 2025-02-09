# frozen_string_literal: true

module Masks::Types
  class InstallationInputType < BaseInputObject
    argument :theme, CamelizedJSON, required: false
    argument :nicknames, CamelizedJSON, required: false
    argument :passwords, CamelizedJSON, required: false
    argument :backup_codes, CamelizedJSON, required: false
    argument :clients, CamelizedJSON, required: false
    argument :actors, CamelizedJSON, required: false
    argument :devices, CamelizedJSON, required: false
    argument :sessions, CamelizedJSON, required: false
  end
end
