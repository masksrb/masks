module Masks
  module ProtectedController
    extend ActiveSupport::Concern

    class_methods do
      def mask(*args, **opts, &block)
        use Masks::ProtectedEndpoint, *args, **opts, &block
      end
    end

    included do
      helper_method :current_client
      helper_method :current_device
      helper_method :current_actor
    end

    def masks_profile_url
      return unless current_actor && current_client

      current_client.profile_url(current_actor, redirect_uri: request.path)
    end

    def masks_session
      request.env["masks.session"]
    end

    def current_device
      masks_session.device.current
    end

    def current_client
      masks_session.client.current
    end

    def current_actor
      masks_session.actor.current
    end
  end
end
