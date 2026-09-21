class ClientLogosController < ApplicationController
  include ServesPictures

  skip_before_action :refuse_blocked_device, only: :show

  def show
    client = Client.find_by(client_id: params[:client_id])

    return head :not_found unless client&.logo_shown_to?(current_actor)

    stamped = params[:v] == client.logo_digest && client.approved?
    caching = stamped ? "public, max-age=#{FOREVER}, immutable" : "private, max-age=#{BRIEFLY}"

    deliver_picture(client.logo_digest, cache_control: caching) do
      [ Pictures::CONTENT_TYPE, client.logo&.resized(Avatars.size(params[:size])) ]
    end
  end
end
