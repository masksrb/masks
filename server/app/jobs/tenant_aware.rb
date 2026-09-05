module TenantAware
  extend ActiveSupport::Concern

  KEY = "tenant".freeze

  def serialize
    super.merge(KEY => Current.tenant&.uuid)
  end

  def deserialize(job_data)
    super
    @tenant_uuid = job_data[KEY]
  end

  def perform_now
    return super if @tenant_uuid.blank?

    Tenant.switch(Tenant.active.find_by!(uuid: @tenant_uuid)) { super }
  end
end
