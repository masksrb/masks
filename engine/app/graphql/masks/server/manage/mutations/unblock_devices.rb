module Masks
  module Server
    module Manage
      module Mutations
        class UnblockDevices < BaseMutation
          argument :ids, [ ID ]

          field :count, Integer, null: false

          def resolve(ids:)
            refuse!("at most #{BlockDevices::MOST} devices at once") if ids.size > BlockDevices::MOST

            count = 0

            ActiveRecord::Base.transaction do
              Masks::Server::Device.blocked.where(id: ids).find_each do |device|
                device.unblock!
                audit!(Masks::Server::Event::DEVICE_UNBLOCKED, device: device)
                count += 1
              end
            end

            { count: count }
          end
        end
      end
    end
  end
end
