module Manage
  module Mutations
    class SignOutDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        device = device!(id)

        device.sign_out!
        audit!(::Event::DEVICE_FORGOTTEN, device: device)

        { device: device }
      end
    end
  end
end
