# frozen_string_literal: true

module Masks::Types
  class EnterInputType < BaseInputObject
    argument :id, ID, required: false
    argument :event, String, required: false
    argument :updates, GraphQL::Types::JSON, required: false
    argument :upload, ApolloUploadServer::Upload, required: false
  end
end
