module Masks
  module Server
    class CleanupJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      GRACE = 7.days
      BATCH = 10_000

      def perform
        Tenant.active.find_each do |tenant|
          Tenant.switch(tenant) { sweep(tenant) }
        end
      end

      private

        def sweep(tenant)
          cutoff = GRACE.ago

          Token.where(expires_at: ...cutoff).delete_all
          Token.where.not(consumed_at: nil).where(consumed_at: ...cutoff).delete_all
          Session.where(expires_at: ...cutoff).delete_all
          Session.where.not(revoked_at: nil).where(revoked_at: ...cutoff).delete_all
          SigningKey.where.not(retired_at: nil).where(retired_at: ...cutoff).delete_all
          Event.where(created_at: ...tenant.event_retention.ago).in_batches(of: BATCH).delete_all
        end
    end
  end
end
