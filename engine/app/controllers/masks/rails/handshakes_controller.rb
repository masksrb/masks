module Masks
  module Rails
    class HandshakesController < ActionController::Base
      include Masks::Rails::Authentication

      STATE = :masks_handshake_state

      layout "masks/rails/plain"

      before_action :require_unconfigured_or_signed_in

      def show
      end

      def create
        started = masks_config.handshake_for(request).start

        session[STATE] = started[:state]

        redirect_to started[:url], allow_other_host: true
      rescue Masks::Client::Error => e
        refuse(e)
      end

      def callback
        registration = masks_config.handshake_for(request).complete(returned, state: session[STATE])

        session.delete(STATE)
        masks_config.store!(request, registration)

        redirect_to Masks::Rails::Engine.routes.url_helpers.start_path
      rescue Masks::Client::Error => e
        refuse(e)
      end

      private

        def returned
          params.permit(:initial_access_token, :iss, :state, :error, :error_description).to_h
        end

        def require_unconfigured_or_signed_in
          return unless masks_config.configured?(request)
          return if masks_signed_in?

          redirect_to masks_config.after_sign_out
        end

        def refuse(error)
          session.delete(STATE)

          @code = error.try(:code).presence || error.class.name.demodulize.underscore
          @description = error.try(:description).presence || error.message

          render :refused, status: :bad_request
        end
    end
  end
end
