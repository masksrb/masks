# frozen_string_literal: true

module Masks::Types
  class EmailInputType < BaseInputObject
    argument :actor_id, String, required: true
    argument :address, String, required: true
    argument :action, String, required: true
  end
end
