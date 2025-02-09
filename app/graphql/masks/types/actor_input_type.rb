# frozen_string_literal: true

module Masks::Types
  class ActorInputType < BaseInputObject
    argument :id, String, required: false
    argument :identifier, String, required: false
    argument :signup, Boolean, required: false
    argument :name, String, required: false
    argument :nickname, String, required: false
    argument :scopes, String, required: false
    argument :reset_backup_codes, Boolean, required: false
    argument :password, String, required: false
    argument :reset_password, Boolean, required: false
  end
end
