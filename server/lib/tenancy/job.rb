module Tenancy
  module Job
    extend ActiveSupport::Concern

    KEY = "tenant".freeze
    EVERY = "*".freeze

    class Homeless < StandardError
      def initialize(job)
        super(
          "#{job} was reached outside any tenant. A job carries the tenant it was enqueued in so " \
          "that it reads the same rows the request did; without one it would perform against " \
          "whichever tenant its worker thread happened to hold last. Enqueue it inside " \
          "Tenant.switch, or declare across_tenants! on it if it is maintenance meant to span " \
          "every tenant."
        )
      end
    end

    included do
      class_attribute :across_tenants, instance_accessor: false, default: false
    end

    class_methods do
      def across_tenants!
        self.across_tenants = true
      end
    end

    def serialize
      super.merge(KEY => enqueued_in)
    end

    def deserialize(job_data)
      super

      @tenant_uuid = job_data[KEY]
    end

    def perform_now
      return super if self.class.across_tenants || @tenant_uuid == EVERY

      held = @tenant_uuid.presence

      return super if held.nil? && Current.tenant

      raise Homeless, self.class.name if held.nil?

      Tenant.switch(Tenant.active.find_by!(uuid: held)) { super }
    end

    private

      def enqueued_in
        return EVERY if self.class.across_tenants

        Current.tenant&.uuid || raise(Homeless, self.class.name)
      end
  end
end
