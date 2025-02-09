# frozen_string_literal: true

module Masks::Mutations
  class HardwareKey < BaseMutation
    input_object_class Masks::Types::HardwareKeyInputType

    field :hardware_key, Masks::Types::HardwareKeyType, null: true
    field :hardware_keys, [Masks::Types::HardwareKeyType], null: true
    field :errors, [String], null: true

    def resolve(**args)
      actor = Masks::Actor.find_by(key: args[:actor_id])

      return { errors: ["unknown actor"] } unless actor

      hardware_keys = actor.hardware_keys
      hardware_key =
        case args[:action]
        when "delete"
          hardware_keys.find_by(external_id: args[:id])
        end

      if args[:action] == "delete"
        hardware_key&.destroy if hardware_key&.valid?
      end

      {
        hardware_key:,
        hardware_keys:,
        errors: hardware_key&.errors&.full_messages,
      }
    end
  end
end
