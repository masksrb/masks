# frozen_string_literal: true

module Masks::Mutations
  class Leave < BaseMutation
    input_object_class Masks::Types::LeaveInputType

    field :entry, Masks::Types::EntryType, null: false

    def resolve(**args)
      entry = Masks::Entries::Leave.enter(context[:session], **args)

      { entry: }
    end
  end
end
