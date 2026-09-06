class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :origin, :session, :device, :ip_address, :user_agent
end
