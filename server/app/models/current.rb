class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :origin, :session
end
