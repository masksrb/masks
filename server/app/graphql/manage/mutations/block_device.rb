module Manage
  module Mutations
    class BlockDevice < BaseMutation
      argument :id, ID

      field :device, Types::DeviceType, null: false

      def resolve(id:)
        { device: device!(id).tap(&:block!) }
      end
    end
  end
end
