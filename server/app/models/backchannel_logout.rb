module BackchannelLogout
  class Refused < StandardError; end

  def self.announce(session)
    origin = session.origin.presence || Current.origin.presence || session.tenant.public_origin

    return if origin.blank?

    session.relying_parties.find_each do |client|
      BackchannelLogoutJob.perform_later(
        client_id: client.client_id,
        subject: Subjects.for(session.actor, client),
        actor: session.actor.uuid,
        sid: session.uuid,
        origin: origin
      )
    end
  end

  def self.deliver!(client, token)
    uri = URI.parse(client.backchannel_logout_uri)

    routable!(client, uri)

    response = Outbound.post(uri, { logout_token: token })

    return true if response.is_a?(Net::HTTPSuccess)

    raise Refused, "#{client.name} answered #{response.code}"
  rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
         OpenSSL::SSL::SSLError, URI::InvalidURIError => e
    raise Refused, "#{client.name} could not be reached: #{e.class}"
  end

  def self.routable!(client, uri)
    return unless client.dynamic?
    return if Rails.env.local?

    raise Refused, "#{client.name} is not reachable over http" unless uri.is_a?(URI::HTTP)

    return if Outbound.routable?(uri)

    raise Refused, "#{client.name} resolves to an address this server will not call"
  end
end
