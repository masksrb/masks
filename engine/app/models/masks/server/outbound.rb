module Masks
  module Server
    module Outbound
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      DEADLINE = 20
      CEILING = 256.kilobytes

      UNROUTABLE = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
        172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
        198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
        ::/96 ::1/128 64:ff9b::/96 64:ff9b:1::/48 100::/64 2002::/16 fc00::/7 fe80::/10 ff00::/8
      ].map { |range| IPAddr.new(range) }.freeze

      class Overflow < StandardError; end
      class Refused < StandardError; end
      class Slow < StandardError; end

      UNREADABLE = [
        Slow, Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, SystemCallError,
        OpenSSL::SSL::SSLError, EOFError, IOError, Zlib::Error
      ].freeze

      class << self
        def problem_with(url)
          uri = URI.parse(url.to_s)
          secure = uri.is_a?(URI::HTTPS) || (::Rails.env.local? && uri.is_a?(URI::HTTP))

          if !secure || uri.host.blank?
            "must be an https address"
          elsif uri.userinfo.present?
            "must not carry a username or password"
          elsif !::Rails.env.local? && !routable?(uri)
            "must resolve to a public address"
          end
        rescue URI::InvalidURIError
          "is not an address"
        end

        def routable?(uri)
          vetted(uri).present?
        end

        def vetted(uri)
          return nil unless uri.is_a?(URI::HTTP)

          public_address(uri.hostname, uri.port)
        end

        def public_address(host, port)
          addresses = resolve(host, port)

          return nil if addresses.empty? || addresses.any? { |address| unroutable?(address) }

          addresses.first
        end

        def resolve(host, port)
          return [] if host.blank?

          Addrinfo.getaddrinfo(host.to_s, port, nil, :STREAM).map do |info|
            held = IPAddr.new(info.ip_address.split("%").first)

            held.ipv4_mapped? ? held.native : held
          end
        rescue SocketError
          []
        end

        def unroutable?(address)
          UNROUTABLE.any? { |range| range.include?(address) } && allowed.none? { |range| range.include?(address) }
        end

        def allowed
          Server.config.outbound_allowed || []
        end

        def fetch!(uri, **options)
          get!(uri, **options).body
        end

        def get!(uri, open: OPEN_TIMEOUT, read: READ_TIMEOUT, ceiling: CEILING, within: nil, headers: {})
          response = request!(uri, Net::HTTP::Get.new(uri, headers), open: open, read: read,
                                                                    ceiling: ceiling + 1, within: within)

          raise Refused, "answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
          raise Refused, "answered with more than #{ceiling / 1.kilobyte}KB" if response.body.bytesize > ceiling

          response
        rescue Slow
          raise Refused, "took longer than #{within || DEADLINE} seconds to answer"
        rescue *UNREADABLE => e
          raise Refused, "could not be read: #{e.class}"
        end

        def request!(uri, request, open: OPEN_TIMEOUT, read: READ_TIMEOUT, ceiling: CEILING, within: nil)
          call(uri, request, open: open, read: read, address: pinned!(uri), ceiling: ceiling, within: within)
        end

        def post(uri, form, open: OPEN_TIMEOUT, read: READ_TIMEOUT, address: nil)
          request = Net::HTTP::Post.new(uri, "Content-Type" => "application/x-www-form-urlencoded")
          request.body = URI.encode_www_form(form)

          call(uri, request, open: open, read: read, address: address || pinned!(uri))
        end

        def post_json(uri, body, headers: {}, open: OPEN_TIMEOUT, read: READ_TIMEOUT, address: nil)
          request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" }.merge(headers))
          request.body = body

          call(uri, request, open: open, read: read, address: address || pinned!(uri))
        end

        def pinned!(uri)
          return nil if ::Rails.env.local?

          vetted(uri) || raise(Refused, "resolves to an address this server will not call")
        end

        def call(uri, request, open:, read:, address: nil, ceiling: CEILING, within: nil)
          kept = +""
          answered = nil

          begin
            Timeout.timeout(within || DEADLINE, Slow) do
              connection(uri, open: open, read: read, address: address).start do |http|
                http.request(request) do |response|
                  answered = response

                  response.read_body do |chunk|
                    kept << chunk
                    raise Overflow if kept.bytesize > ceiling
                  end
                end
              end
            end
          rescue Overflow
            answered.instance_variable_set(:@read, true)
          end

          answered.body = kept.byteslice(0, ceiling)
          answered
        end

        def body(response)
          response.body.to_s.byteslice(0, CEILING)
        end

        private

          def connection(uri, open:, read:, address:)
            http = Net::HTTP.new(uri.hostname, uri.port)
            http.ipaddr = address.to_s if address
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = open
            http.read_timeout = read
            http.max_retries = 0

            http
          end
      end
    end
  end
end
