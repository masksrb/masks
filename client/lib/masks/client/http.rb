module Masks
  module Client
    module HTTP
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      READ_LIMIT = 1 << 20
      FETCH_LIMIT = 8 << 20

      module_function

      def get(url, headers = {})
        request(Net::HTTP::Get.new(URI.parse(url.to_s), default_headers.merge(headers)))
      end

      def post_form(url, form, headers = {})
        encoded(Net::HTTP::Post, url, form, headers)
      end

      def delete_form(url, form, headers = {})
        encoded(Net::HTTP::Delete, url, form, headers)
      end

      def encoded(verb, url, form, headers)
        request(form_request(verb, url, form, headers))
      end

      def form_request(verb, url, form, headers)
        request = verb.new(URI.parse(url.to_s), default_headers.merge(headers))
        request.body = URI.encode_www_form(form)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request
      end

      def post_json(url, body, headers = {})
        json(Net::HTTP::Post, url, body, headers)
      end

      def put_json(url, body, headers = {})
        json(Net::HTTP::Put, url, body, headers)
      end

      def delete(url, headers = {})
        request(Net::HTTP::Delete.new(URI.parse(url.to_s), default_headers.merge(headers)))
      end

      def fetch(url, headers = {})
        deliver(Net::HTTP::Get.new(checked(URI.parse(url.to_s)), headers), limit: FETCH_LIMIT)
      end

      def json(verb, url, body, headers)
        uri = URI.parse(url.to_s)
        request = verb.new(uri, default_headers.merge(headers))
        request.body = JSON.generate(body)
        request["Content-Type"] = "application/json"

        self.request(request)
      end

      def default_headers
        { "Accept" => "application/json", "User-Agent" => "masks/#{Masks::VERSION}" }
      end

      def request(request)
        parse(deliver(request))
      end

      def deliver(request, limit: READ_LIMIT)
        uri = checked(request.uri)
        embedded = Masks::Client.embedded_for(uri)

        return embedded.deliver(request, limit: limit) if embedded

        Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| limit ? limited(http, request, limit) : http.request(request) }
      rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise Unavailable, Masks::Client.saying("unreachable", uri.host)
      end

      def checked(uri)
        return uri if uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty?
        return uri if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? && (Masks::Client.plain_http? || loopback?(uri.hostname))

        if uri.is_a?(URI::HTTP)
          raise Insecure, Masks::Client.saying("plain_http", Nonces.origin(uri))
        end

        raise Insecure.of("not_http", uri)
      end

      def loopback?(host)
        name = host.to_s.downcase

        return true if name == "localhost" || name.end_with?(".localhost")

        IPAddr.new(name).loopback?
      rescue IPAddr::Error
        false
      end

      def limited(http, request, limit)
        http.request(request) do |response|
          body = +""

          response.read_body do |chunk|
            body << chunk
            raise Refused.new("server_error", "#{request.uri.host} answered with more than #{limit} bytes") if body.bytesize > limit
          end

          response.body = body
        end
      end

      def parse(response)
        body = decoded(response)

        unless response.is_a?(Net::HTTPSuccess)
          refusal = Unregistered.raised_by?(body) ? Unregistered : Refused
          code, description = refused_with(body, response)

          raise refusal.new(code, description, status: response.code.to_i)
        end

        body
      end

      def decoded(response)
        raw = response.body.to_s
        return {} if raw.strip.empty?

        held = JSON.parse(raw)

        return held if held.is_a?(Hash)
        return {} unless response.is_a?(Net::HTTPSuccess)

        raise Refused.new(*Masks::Client.failure("not_an_object", origin(response)), status: response.code.to_i)
      rescue JSON::ParserError
        return {} unless response.is_a?(Net::HTTPSuccess)

        raise Refused.new(*Masks::Client.failure("not_json", origin(response)), status: response.code.to_i)
      end

      def refused_with(body, response)
        return Masks::Client.failure("answered_status", origin(response), response.code.to_i) if body["error"].to_s.empty?

        [ body["error"], body["error_description"] || response.message ]
      end

      def origin(response)
        uri = response.uri

        uri ? Nonces.origin(uri) : "the server"
      end
    end
  end
end
