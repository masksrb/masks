module Masks
  module Rails
    class LogoutsController < BaseController
      skip_forgery_protection

      def create
        return refuse("invalid_request", "logout_token is required") if params[:logout_token].blank?

        logout = masks_session.logout_token(params[:logout_token])

        masks_config.logged_out!(request, logout)

        response.headers["Cache-Control"] = "no-store"

        head :ok
      rescue Masks::Client::InvalidToken => e
        refuse("invalid_request", e.message)
      rescue Masks::Rails::Configuration::Unconfigured => e
        refuse("invalid_request", e.message)
      end

      private

        def refuse(code, description)
          response.headers["Cache-Control"] = "no-store"

          render json: { "error" => code, "error_description" => description },
                 status: :bad_request
        end
    end
  end
end
