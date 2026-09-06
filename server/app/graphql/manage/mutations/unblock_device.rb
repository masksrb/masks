module Manage
  module Mutations
    class UnblockDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        device = device!(id)

        device.unblock!
        audit!(::Event::DEVICE_UNBLOCKED, device: device)

        { device: device }
      end
    end
  end
end
