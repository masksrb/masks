module Masks
  module Server
    class IdleAccountsJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        each_tenant(Tenant.active.idling) { |tenant| IdleAccounts.sweep(tenant) }
      end
    end
  end
end
