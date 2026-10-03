module Masks
  module Server
    class Current < ActiveSupport::CurrentAttributes
      attribute :tenant, :origin, :device, :ip_address, :user_agent, :previewing, :organization,
                :authorization_details_declared
    end
  end
end
