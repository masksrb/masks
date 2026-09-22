module Masks
  module Server
    class ThemesController < ApplicationController
      SEALED = "default-src 'none'".freeze

      skip_before_action :refuse_blocked_device

      def show
        theme = Themes.find(tenant: current_tenant, digest: params[:digest])

        return head :not_found if theme.nil?

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Content-Security-Policy"] = SEALED
        response.headers["Cache-Control"] = "public, max-age=#{1.year.to_i}, immutable"

        send_data theme.body, type: "text/css; charset=utf-8", disposition: "inline"
      end
    end
  end
end
