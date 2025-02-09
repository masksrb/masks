# frozen_string_literal: true

module Masks::Mutations
  class Login < BaseMutation
    input_object_class Masks::Types::LoginInputType

    field :login, Masks::Types::LoginType, null: false

    def resolve(**args)
      entry = Masks::Entries::Authentication.enter(context[:session], **args)

      { entry: }
    end
  end
end
