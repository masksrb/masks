module Masks
  module Server
    module Host
      extend ActiveSupport::Concern

      included do
        helper_method :masks_actor if respond_to?(:helper_method)
      end

      def masks_actor
        return @masks_actor if defined?(@masks_actor)

        @masks_actor = Server.actor_for(request)
      end

      def require_masks_actor!
        redirect_to masks_server.login_path(return_to: request.fullpath) unless masks_actor
      end
    end
  end
end
