module Masks
  class ProvidersController < ApplicationController
    use Masks::ProviderEndpoint

    include Masks::LoginController
    include Masks::FrontendController

    masks_layout

    # before_action :invalid_request, unless: :masks_login

    # def invalid_request
    #   provider = masks_login&.provider

    #   byebug
    #   render_error status: 400,
    #                prompt: "sso-error",
    #                error: "invalid-sso",
    #                origin: masks_login&.origin,
    #                provider:
    #                  (
    #                    if provider
    #                      { name: provider&.name, type: provider&.public_type }
    #                    else
    #                      nil
    #                    end
    #                  )
    # end

    def callback
      origin = masks_login.dig(:extras, :origin)

      return redirect_to origin if origin

      render_masks(prompt: "sso-error")
    end
  end
end
