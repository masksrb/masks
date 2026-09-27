module Masks
  module Server
    class IdleAccountsJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        Tenant.active.where("suspend_after IS NOT NULL OR delete_after IS NOT NULL").find_each do |tenant|
          Tenant.switch(tenant) { IdleAccounts.sweep(tenant) }
        end
      end
    end
  end
end
