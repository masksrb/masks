module Masks
  module Rails
    class HandshakesController < BaseController
      before_action :require_unconfigured_or_signed_in

      def show
        return begin! unless masks_config.configured?(request)

        @can_disconnect = masks_config.can_forget?
      end

      def create
        begin!
      end

      def callback
        pending = masks_handshakes.claim(params[:state])

        return stale if pending.nil?

        registration = masks_config.handshake_for(request).complete(returned, state: pending.id)

        masks_config.store!(request, registration)

        redirect_to Masks::Rails::Engine.routes.url_helpers.start_path
      rescue Masks::Client::Error => e
        refuse(e)
      end

      def destroy
        return redirect_to(masks_config.after_sign_out) unless masks_signed_in?
        return redirect_to(masks_handshake_path) unless masks_config.can_forget?

        forget_upstream

        masks_config.forget!(request)
        masks_forget

        redirect_to masks_handshake_path
      rescue Masks::Client::Error => e
        refuse(e)
      end

      private

        def begin!
          pending = masks_handshakes.open
          started = masks_config.handshake_for(request).start(state: pending.id)

          redirect_to started[:url], allow_other_host: true
        rescue Masks::Client::Error => e
          refuse(e)
        end

        def forget_upstream
          masks_registration&.delete
        rescue Masks::Client::Unregistered
          false
        end

        def returned
          params.permit(:initial_access_token, :iss, :state, :error, :error_description).to_h
        end

        def require_unconfigured_or_signed_in
          return unless masks_config.configured?(request)
          return if masks_signed_in?

          redirect_to masks_config.after_sign_out
        end

        def stale
          @code = "invalid_state"
          @description = "that connection request is not one this browser started, or it expired"

          render :refused, status: :bad_request
        end

        def refuse(error)
          @code = error.try(:code).presence || error.class.name.demodulize.underscore
          @description = error.try(:description).presence || error.message

          render :refused, status: :bad_request
        end
    end
  end
end
