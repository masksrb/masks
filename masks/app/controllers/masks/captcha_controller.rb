# frozen_string_literal: true

module Masks
  # Login endpoint.
  #
  # Handles GET, POST and DELETE, eventually redirecting back
  # to the given redirect_uri with a valid token once logged in.
  class CaptchaController < Masks::ApplicationController
    include Sessions::Controller

    layout 'masks/client'

    def show
      render 'masks/device_policy/not_found'
    end

    def verify
      captcha.verify(request)

      head :ok
    end

    private

    def captcha
      @captcha ||= Masks.adapter(params[:captcha])
    end
  end
end
