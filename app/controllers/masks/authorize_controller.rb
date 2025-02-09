module Masks
  class AuthorizeController < ApplicationController
    include InternalController
    include FrontendController

    rescue_from MissingClientError do
      render_error status: 404, prompt: "missing-client"
    end

    def new
      @client =
        if request.GET[:client_id]&.presence
          client = Masks.client(request.GET[:client_id], internal: false)
        elsif params[:client_id]
          client = Masks.client(params[:client_id], internal: true)
        elsif Masks.conf.internal_client&.present?
          Masks.client(Masks.conf.internal, internal: true)
        elsif Masks.conf.theme_homepage
          return redirect_to Masks.conf.theme_homepage
        end

      authorize
    end

    private

    def authorize
      entry = Entries::Authorization.enter(masks_session, client: @client)
      json = entry.to_gql

      frontend_props(**json)

      headers["X-Masks-Entry-Id"] = entry.id

      status = entry.error ? 400 : 200

      respond_to do |format|
        format.html { render "app", status: }
        format.json { render json:, status: }
      end
    end
  end
end
