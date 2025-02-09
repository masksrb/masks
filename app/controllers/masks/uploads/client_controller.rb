module Masks
  module Uploads
    class ClientController < ManagersController
      def create
        client = Masks.client(params[:client_id])

        if client
          client.logo_file = params[:file]

          render json: { url: Masks.storage_url(client.logo) }
        else
          render status: 404, json: {}
        end
      end
    end
  end
end
