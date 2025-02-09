# frozen_string_literal: true

module Masks::Mutations
  class Phone < BaseMutation
    input_object_class Masks::Types::PhoneInputType

    field :phone, Masks::Types::PhoneType, null: true
    field :phones, [Masks::Types::PhoneType], null: true
    field :errors, [String], null: true

    def resolve(**args)
      actor = Masks.actors.identify(key: args[:actor_id], required: true)

      return { errors: ["unknown actor"] } unless actor

      phones = actor.phones
      phone =
        case args[:action]
        when "create"
          phones.build(number: args[:number])
        when "delete"
          p = phones.find_by(number: args[:number])
          p.mark_for_destruction
          p
        end

      if args[:action] == "delete"
        phone&.destroy if phone.valid?
      else
        phone.save
      end

      { phone:, phones:, errors: phone&.errors&.full_messages }
    end
  end
end
