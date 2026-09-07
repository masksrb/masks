module Outbound
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  CEILING = 256.kilobytes

  UNROUTABLE = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  class << self
    def routable?(uri)
      return false unless uri.is_a?(URI::HTTP)

      addresses = resolve(uri)

      addresses.any? && addresses.none? { |address| unroutable?(address) }
    end

    def resolve(uri)
      Addrinfo.getaddrinfo(uri.hostname, uri.port, nil, :STREAM).map do |info|
        held = IPAddr.new(info.ip_address.split("%").first)

        held.ipv4_mapped? ? held.native : held
      end
    rescue SocketError
      []
    end

    def unroutable?(address)
      UNROUTABLE.any? { |range| range.include?(address) }
    end

    def get(uri, open: OPEN_TIMEOUT, read: READ_TIMEOUT)
      call(uri, Net::HTTP::Get.new(uri), open: open, read: read)
    end

    def post(uri, form, open: OPEN_TIMEOUT, read: READ_TIMEOUT)
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/x-www-form-urlencoded")
      request.body = URI.encode_www_form(form)

      call(uri, request, open: open, read: read)
    end

    def call(uri, request, open:, read:)
      Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open,
        read_timeout: read
      ) { |http| http.request(request) }
    end

    def body(response)
      response.body.to_s.byteslice(0, CEILING)
    end
  end
end
