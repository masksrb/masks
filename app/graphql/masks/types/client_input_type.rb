# frozen_string_literal: true

module Masks::Types
  class ClientInputType < BaseInputObject
    argument :id, ID, required: false

    Masks::Client.settings.each do |col, conf|
      argument col, conf[:graphql], required: false
    end

    argument :styles, ApolloUploadServer::Upload, required: false
    argument :remove_styles, Boolean, required: false
  end
end
