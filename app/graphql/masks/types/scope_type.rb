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
      Masks.installation.scopes.detail(object)
    end

    def hidden
      Masks.installation.scopes.hidden?(object)
    end
  end
end
