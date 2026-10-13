module Masks
  module Rails
    class LogoutsController < BaseController
      skip_forgery_protection

      def create
        return refuse("invalid_request", "logout_token is required") if params[:logout_token].blank?

        logout = masks_session.logout_token(params[:logout_token])
        issuer = masks_config.issuer_for(request).to_s

        return refuse("invalid_request", "that logout token was already used") unless masks_cache.first_logout?(issuer, logout)

        masks_cache.depart!(issuer, logout)
        masks_config.logged_out!(request, logout)

        response.headers["Cache-Control"] = "no-store"

        head :ok
      rescue Masks::Client::InvalidToken, Masks::Rails::Configuration::Unconfigured => e
        refuse("invalid_request", e.message)
      rescue Masks::Client::Unreachable, Masks::Rails::Cache::Unavailable => e
        refuse("temporarily_unavailable", e.message, status: :service_unavailable)
      end

      private

        def refuse(code, description, status: :bad_request)
          response.headers["Cache-Control"] = "no-store"

          render json: { "error" => code, "error_description" => description }, status: status
        end
    end
  end
end
