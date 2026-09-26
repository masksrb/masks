module Masks
  module Server
    class CodeFactorsController < ApplicationController
      before_action :require_actor

      def create
        factor = params[:factor].to_s

        return refuse(t("code_factors.unoffered")) unless CodeFactors.offered?(current_actor, factor)
        return refuse(t("code_factors.unconfirmed")) unless CodeFactors.confirmed?(current_actor, factor)
        return refuse(t("code_factors.undeliverable")) unless CodeFactors.deliverable?(factor)

        CodeFactors.enable!(current_actor, factor) unless CodeFactors.held?(current_actor, factor)

        redirect_to root_path, notice: t("code_factors.enabled.#{factor}")
      end

      def destroy
        factor = params[:factor].to_s

        return refuse(t("code_factors.unoffered")) unless CodeFactors.known?(factor)

        CodeFactors.disable!(current_actor, factor)

        redirect_to root_path, notice: t("code_factors.disabled.#{factor}")
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end

        def refuse(message)
          redirect_to root_path, alert: message
        end
    end
  end
end
