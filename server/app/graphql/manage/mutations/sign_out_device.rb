module Manage
  module Mutations
    class SignOutDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        { device: device!(id).sign_out! }
      end
    end
  end
end
