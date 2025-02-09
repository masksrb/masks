# frozen_string_literal: true

module Masks::Types
  class IconType < BaseObject
    field :light, String, null: true
    field :dark, String, null: true
  end
end
