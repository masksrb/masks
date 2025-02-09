# frozen_string_literal: true

module Masks::Types
  class PhoneInputType < BaseInputObject
    argument :actor_id, String, required: true
    argument :number, String, required: true
    argument :action, String, required: true
  end
end
