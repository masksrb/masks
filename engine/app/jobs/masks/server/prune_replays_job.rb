module Masks
  module Server
    class PruneReplaysJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        Tenant.active.find_each do |tenant|
          Tenant.switch(tenant) { Replay.prune! }
        end
      end
    end
  end
end
