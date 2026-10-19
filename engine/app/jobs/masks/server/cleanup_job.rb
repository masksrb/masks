module Masks
  module Server
    class CleanupJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      GRACE = 7.days
      BATCH = 10_000

      class Incomplete < StandardError; end

      def perform
        failed = Tenant.active.find_each.filter_map do |tenant|
          Tenant.switch(tenant) { sweep(tenant) }
          nil
        rescue StandardError => e
          ::Rails.error.report(e, context: { tenant: tenant.subdomain })
          tenant.subdomain
        end

        raise Incomplete, "cleanup failed for #{failed.join(', ')}" if failed.any?
      end

      private

        def sweep(tenant)
          cutoff = GRACE.ago

          sweep_tokens(cutoff)
          ended = Session.where(expires_at: ...cutoff).or(Session.where(revoked_at: ...cutoff))
          ended.where.not(id: Token.live.where.not(session_id: nil).select(:session_id)).delete_all
          SigningKey.where.not(retired_at: nil).where(retired_at: ...cutoff).delete_all
          Event.where(created_at: ...tenant.event_retention.ago).in_batches(of: BATCH).delete_all
          Members.purge_lapsed!
          Replay.where(expires_at: ...Time.current).in_batches(of: BATCH).delete_all
          ReleasedNickname.lapsed.in_batches(of: BATCH).delete_all
        end

        def sweep_tokens(cutoff)
          Token.where(root_id: nil).ended_before(cutoff).in_batches(of: BATCH) do |roots|
            ids = roots.pluck(:id)
            kept = Token.where(root_id: ids).where("LEAST(consumed_at, expires_at) >= ?", cutoff).distinct.pluck(:root_id)

            Token.families(ids - kept).delete_all
          end

          Token.where.not(kind: RefreshToken.sti_name).ended_before(cutoff)
            .where.not(Token.where("children.parent_id = tokens.id").from("tokens children").arel.exists)
            .in_batches(of: BATCH).delete_all
        end
    end
  end
end
