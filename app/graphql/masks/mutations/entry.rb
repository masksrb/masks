# frozen_string_literal: true

module Masks::Mutations
  class Entry < BaseMutation
    field :entry, Masks::Types::EntryType, null: false

    def resolve(**args)
      entry = context[:entry]

      { entry: context[:entry] }
    end
  end
end
