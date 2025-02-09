# frozen_string_literal: true

module Masks::Types
  class OtpSecretInputType < BaseInputObject
    argument :actor_id, ID, required: true
    argument :id, ID, required: true
    argument :action, String, required: true
  end
end
