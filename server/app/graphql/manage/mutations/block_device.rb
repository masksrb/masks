module Manage
  module Mutations
    class BlockDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        device = device!(id)

        device.block!
        audit!(::Event::DEVICE_BLOCKED, device: device)

        { device: device }
      end
    end
  end
end
