module Masks
  class ProvidersController < ApplicationController
    include InternalController
    include FrontendController

    rescue_from MissingClientError do
      invalid_request
    end

    def invalid_request(entry = nil)
      provider = entry&.provider

      render_error status: 400,
                   prompt: "sso-error",
                   error: "invalid-sso",
                   origin: entry&.origin,
                   provider:
                     (
                       if provider
                         { name: provider&.name, type: provider&.public_type }
                       else
                         nil
                       end
                     )
    end

    def callback
      entry =
        Entries::SingleSignOn.enter(
          masks_session,
          provider_id: params[:provider_id],
        )
      origin = entry.extras[:origin]

      if origin
        redirect_to origin
      else
        raise SingleSignOnError
      end
    rescue => e
      raise if Rails.env.development?

      invalid_request(entry)
    end
  end
end
