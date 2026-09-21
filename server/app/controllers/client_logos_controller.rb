class ClientLogosController < ApplicationController
  SEALED = "default-src 'none'; sandbox".freeze
  FOREVER = 1.year.to_i
  BRIEFLY = 5.minutes.to_i

  skip_before_action :refuse_blocked_device, only: :show

  def show
    client = Client.find_by(client_id: params[:client_id])
    logo = client && (client.shown_logo || (current_actor&.manages? ? client.logo : nil))

    return head :not_found if logo.nil?

    stamped = params[:v] == logo.digest

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = SEALED
    response.headers["Cache-Control"] = stamped && client.approved? ? "public, max-age=#{FOREVER}, immutable" : "private, max-age=#{BRIEFLY}"
    response.headers["ETag"] = %("#{logo.digest}")

    return head :not_modified if request.headers["If-None-Match"].to_s.include?(logo.digest)

    send_data logo.resized(Avatars.size(params[:size])), type: logo.content_type, disposition: "inline"
  end
end
