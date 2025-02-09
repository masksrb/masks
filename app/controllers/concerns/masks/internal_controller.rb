module Masks
  module InternalController
    extend ActiveSupport::Concern

    included do
      rescue_from Masks::LoggedOut do |e|
        redirect_to e.redirect_uri
      end

      helper_method :current_client,
                    :current_manager,
                    :current_actor,
                    :current_device
    end

    class_methods do
      CALLBACK_ARGS = %i[only except if unless]

      def managers_only(**opts)
        mask(**opts.merge(managers_only: true))
      end

      def mask(**opts)
        before_action(**opts.slice(*CALLBACK_ARGS)) do |controller|
          controller.send(:masks_entry, **opts.except(*CALLBACK_ARGS))
        end
      end
    end

    private

    def masks_session
      Masks::Session.env(request.env)
    end

    def masks_install
      @masks_install ||= Masks.installation
    end

    def masks_entry(**opts)
      Masks::Entries::Request.env(request.env, **(masks_opts.merge(**opts)))
    end

    def masks_opts
      @masks_opts ||= {}
    end

    delegate :current_client,
             :current_manager,
             :current_actor,
             :current_device,
             to: :masks_session
  end
end
