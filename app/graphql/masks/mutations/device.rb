# frozen_string_literal: true

module Masks::Mutations
  class Device < BaseMutation
    input_object_class Masks::Types::DeviceInputType

    field :device, Masks::Types::DeviceType, null: true
    field :errors, [String], null: true

    def resolve(**args)
      device = Masks::Device.find_by(public_id: args[:id])

      if device
        if args[:block]
          device.block
        elsif args[:unblock]
          device.unblock
        elsif args[:rotate]
          device.rotate
        end

        device.save
      end

      { errors: device&.errors&.full_messages, device: }
    end
  end
end
