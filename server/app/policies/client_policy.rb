class ClientPolicy < Policy
  checks :client_is_known, :redirect_uri_is_registered

  delegate :client, :redirect_uri, to: :subject

  private

    def client_is_known
      deny!("invalid_client", "no client is registered with that client_id") if client.nil?
    end

    def redirect_uri_is_registered
      if redirect_uri.blank?
        deny!("invalid_request", "redirect_uri is required")
      elsif !client.redirect_uri?(redirect_uri)
        deny!("invalid_request", "redirect_uri is not registered for this client")
      end
    end
end
