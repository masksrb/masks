# frozen_string_literal: true

module Masks::Types
  class DeletionInputType < BaseInputObject
    argument :id, String, required: true
    argument :type, String, required: true
  end
end
