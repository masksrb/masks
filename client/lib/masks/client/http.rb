module Masks
  module Client
    module HTTP
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      module_function

      def get(url, headers = {})
        request(Net::HTTP::Get.new(URI.parse(url.to_s), default_headers.merge(headers)))
      end

      def post_form(url, form, headers = {})
        uri = URI.parse(url.to_s)
        request = Net::HTTP::Post.new(uri, default_headers.merge(headers))
        request.body = URI.encode_www_form(form)
        request["Content-Type"] = "application/x-www-form-urlencoded"

        self.request(request)
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
        uri = request.uri

        response = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.request(request) }

        parse(response)
      rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise Unreachable, "#{uri.host} is unreachable (#{e.class})"
      end

      def parse(response)
        body = begin
          JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          {}
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise Rejected.new(
            body["error"] || "http_#{response.code}",
            body["error_description"] || response.message,
            status: response.code.to_i
          )
        end

        body
      end
    end
  end
end
