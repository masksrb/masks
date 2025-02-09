# frozen_string_literal: true

module Masks::Mutations
  class Enter < BaseMutation
    input_object_class Masks::Types::EnterInputType

    field :entry, Masks::Types::EntryType, null: false

    def resolve(**args)
      entry =
        if context[:entry]
          context[:entry]
        else
          Masks::Entries::Authentication.enter(context[:session], **args)
        end

      { entry: }
    end
  end
end
