module BackchannelLogout
  class Refused < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def self.announce(session)
    origin = session.origin.presence || Current.origin.presence || session.tenant.public_origin

    return if origin.blank?

    session.relying_parties.find_each do |client|
      BackchannelLogoutJob.perform_later(
        client_id: client.client_id,
        subject: session.actor.uuid,
        sid: session.uuid,
        origin: origin
      )
    end
  end

  def self.deliver!(client, token)
    uri = URI.parse(client.backchannel_logout_uri)

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ) do |http|
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/x-www-form-urlencoded")
      request.body = URI.encode_www_form(logout_token: token)

      http.request(request)
    end

    return true if response.is_a?(Net::HTTPSuccess)

    raise Refused, "#{client.name} answered #{response.code}"
  rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
         OpenSSL::SSL::SSLError, URI::InvalidURIError => e
    raise Refused, "#{client.name} could not be reached: #{e.class}"
  end
end
