module Masks
  module Server
    class HealthCheckJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        server = Health.server_results
        failing = Hash.new { |held, name| held[name] = [] }

        begin
          each_tenant do |tenant|
            Health.store!(server + Health.tenant_results).select(&:failing?).each { |row| failing[row.name] << tenant.subdomain }
          end
        ensure
          Health.remember_all!(failing)
        end
      end
    end
  end
end
