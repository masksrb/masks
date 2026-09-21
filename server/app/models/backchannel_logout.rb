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

    response = Outbound.post(uri, { logout_token: token }, address: routable!(client, uri))

    return true if response.is_a?(Net::HTTPSuccess)

    raise Refused, "#{client.name} answered #{response.code}"
  rescue *Outbound::UNREADABLE, URI::InvalidURIError => e
    raise Refused, "#{client.name} could not be reached: #{e.class}"
  end

  def self.routable!(client, uri)
    return unless client.dynamic?
    return if Rails.env.local?

    raise Refused, "#{client.name} is not reachable over http" unless uri.is_a?(URI::HTTP)

    Outbound.vetted(uri) || raise(Refused, "#{client.name} resolves to an address this server will not call")
  end
end
