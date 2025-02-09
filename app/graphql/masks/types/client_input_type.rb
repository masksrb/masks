# frozen_string_literal: true

module Masks::Types
  class ClientInputType < BaseInputObject
    argument :id, ID, required: false

    Masks::Client.settings.each do |col, conf|
      argument col, conf[:graphql], required: false
    end
  end
end
