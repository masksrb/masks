# frozen_string_literal: true

module Masks::Types
  class ServerInputType < BaseInputObject
    Masks::Modes::Server.settings_json.each do |k, setting|
      argument k, setting[:graphql], required: false
    end
  end
end
