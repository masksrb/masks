module BackchannelLogout
  class Refused < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  UNROUTABLE = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

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

    routable!(client, uri)

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

  def self.routable!(client, uri)
    return unless client.dynamic?
    return if Rails.env.local?

    raise Refused, "#{client.name} is not reachable over http" unless uri.is_a?(URI::HTTP)

    addresses = Addrinfo.getaddrinfo(uri.hostname, uri.port, nil, :STREAM).map do |info|
      held = IPAddr.new(info.ip_address.split("%").first)

      held.ipv4_mapped? ? held.native : held
    end

    raise Refused, "#{client.name} resolves to nothing" if addresses.empty?

    return unless addresses.any? { |address| UNROUTABLE.any? { |range| range.include?(address) } }

    raise Refused, "#{client.name} resolves to an address this server will not call"
  rescue SocketError => e
    raise Refused, "#{client.name} could not be reached: #{e.class}"
  end
end
