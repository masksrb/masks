# frozen_string_literal: true

module Masks::Types
  class HardwareKeyInputType < BaseInputObject
    argument :actor_id, ID, required: true
    argument :id, ID, required: true
    argument :action, String, required: true
  end
end
