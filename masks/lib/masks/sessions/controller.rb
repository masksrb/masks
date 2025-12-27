module Masks
  module Sessions
    module Controller
      extend ActiveSupport::Concern

      included do
        helper_method :masks_session, :device
      end

      def masks_session
        Masks.sessions.current(request)
      end

      delegate :device, to: :masks_session

      def throttle!(key, reset: false)
        if reset
          masks_session.throttle.reset(key)
        else
          masks_session.throttle.increment(key)
        end
      end

      def throttled?(key, limit:)
        masks_session.throttle.exceeded?(key, limit:)
      end

      def masks_debug
        @masks_debug ||= OpenStruct.new(
          app: Rails.application.name,
          version: Masks::VERSION,
          request_id: request.request_id,
          controller: controller_name,
          action: action_name,
        )
      end

      def masks_dev?
        !Masks.production?
      end
    end
  end
end
