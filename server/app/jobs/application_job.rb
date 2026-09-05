class ApplicationJob < ActiveJob::Base
  include TenantAware
end
