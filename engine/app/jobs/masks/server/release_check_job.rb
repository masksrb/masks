module Masks
  module Server
    class ReleaseCheckJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      def perform
        return unless ::Rails.configuration.masks.release_check

        found = Release.check!

        return if found.nil?

        each_tenant do
          Event.record!(Event::RELEASE_AVAILABLE, by: nil, version: found["version"], url: found["url"],
                                                  operator_step: found["operator_step"])
        end
      end
    end
  end
end
