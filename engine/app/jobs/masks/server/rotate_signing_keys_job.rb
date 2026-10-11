module Masks
  module Server
    class RotateSigningKeysJob < ApplicationJob
      queue_as :maintenance
      across_tenants!

      PUBLISHED_FOR = 1.day

      def perform
        Tenant.active.where.not(key_rotation_days: nil).find_each do |tenant|
          Tenant.switch(tenant) { advance(tenant) }
        end
      end

      private

        def advance(tenant)
          staged = SigningKey.staged.first

          if staged
            return unless staged.created_at <= PUBLISHED_FOR.ago

            staged.activate!
            Event.record!(Event::SIGNING_KEY_ACTIVATED, by: nil, kid: staged.kid, scheduled: true)
          elsif due?(tenant)
            staged = SigningKey.stage!(tenant: tenant)
            Event.record!(Event::SIGNING_KEY_STAGED, by: nil, kid: staged.kid, scheduled: true)
          end
        end

        def due?(tenant)
          active = SigningKey.active.first
          active.nil? || active.activated_at <= (tenant.key_rotation_days.days - PUBLISHED_FOR).ago
        end
    end
  end
end
