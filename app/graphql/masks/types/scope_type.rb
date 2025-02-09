# frozen_string_literal: true

module Masks::Types
  class ScopeType < BaseObject
    field :name, String, null: false
    field :detail, String, null: true
    field :hidden, Boolean, null: true

    def name
      object
    end

    def detail
      Masks::Scopes.lookup(object)[:detail]
    end

    def hidden
      Masks::Scopes.lookup(object)[:hidden]
    end
  end
end
