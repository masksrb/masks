# frozen_string_literal: true

module Masks::Types
  class LeaveInputType < BaseInputObject
    argument :id, ID, required: false
    argument :logout, Boolean, required: false
  end
end
