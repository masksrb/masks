module Manage
  module Mutations
    class UnblockDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        { device: device!(id).tap(&:unblock!) }
      end
    end
  end
end
