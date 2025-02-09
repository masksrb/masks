# frozen_string_literal: true

module Masks::Types
  class ClientInputType < BaseInputObject
    argument :id, ID, required: false
    argument :name, String, required: false
    argument :secret, String, required: false
    argument :type, String, required: false
    argument :redirect_uris, String, required: false
    argument :scopes, GraphQL::Types::JSON, required: false

    argument :internal, Boolean, required: false
    argument :pkce, Boolean, required: false

    Masks::Client.settings.each do |col, conf|
      argument col, conf[:graphql], required: false
    end
  end
end
