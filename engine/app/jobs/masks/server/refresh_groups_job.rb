module Masks
  module Server
    class RefreshGroupsJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        each_tenant { refresh }
      end

      private

        def refresh
          Group.sourced.find_each(&:refresh!)
        end
    end
  end
end
