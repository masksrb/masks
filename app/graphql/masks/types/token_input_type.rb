# frozen_string_literal: true

module Masks::Types
  class TokenInputType < BaseInputObject
    # For new tokens...
    argument :name, String, required: false
    argument :type, String, required: false
    argument :actor, String, required: false
    argument :client, String, required: false
    argument :scopes, [String], required: false
    argument :expiry, String, required: false

    # For revocation...
    argument :id, String, required: false
    argument :revoked, Boolean, required: false
  end
end
