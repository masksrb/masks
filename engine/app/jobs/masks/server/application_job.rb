module Masks
  module Server
    class ApplicationJob < ActiveJob::Base
      include Tenancy::Job

      class Incomplete < StandardError; end

      private

        def each_tenant(scope = Tenant.active)
          failed = scope.find_each.filter_map do |tenant|
            Tenant.switch(tenant) { yield tenant }
            nil
          rescue StandardError => e
            report_tenant_failure(tenant, e)
            tenant.subdomain
          end

          JobFailures.record(self.class.name, failed)

          raise Incomplete, "#{self.class.name.demodulize} failed for #{failed.join(', ')}" if failed.any?
        end

        def report_tenant_failure(tenant, error)
          ::Rails.error.report(error, context: { tenant: tenant.subdomain, job: self.class.name })

          Tenant.switch(tenant) do
            Event.record!(Event::JOB_FAILED, by: nil, job: self.class.name.demodulize, error: error.class.name, message: error.message.to_s[0, 200])
          end
        rescue StandardError => e
          ::Rails.logger.warn("#{self.class.name} could not record its failure in #{tenant.subdomain}: #{e.message}")
        end
    end
  end
end
