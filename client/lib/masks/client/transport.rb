module Masks
  module Client
    class Transport
      VERBS = {
        "GET" => Net::HTTP::Get, "HEAD" => Net::HTTP::Head, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
        "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete
      }.freeze

      attr_reader :origins, :key

      def initialize(*origins, tokens: nil, key: nil, &renew)
        raise ArgumentError, "a transport needs the origins it may send its tokens to" if origins.empty?
        raise ArgumentError, "a transport needs tokens or a way to fetch them" if tokens.nil? && renew.nil?

        @origins = origins.flatten.map { |origin| Nonces.origin(HTTP.checked(URI.parse(origin.to_s))) }.uniq.freeze
        @tokens = tokens
        @key = key && Key.from(key)
        @renew = renew
        @lock = Mutex.new
        @nonces = Nonces.new
      end

      def tokens
        @lock.synchronize do
          @tokens = @renew.call(@tokens) if @renew && (@tokens.nil? || @tokens.expired?)
          @tokens
        end
      end

      def get(url, headers: {})
        request("GET", url, headers: headers)
      end

      def head(url, headers: {})
        request("HEAD", url, headers: headers)
      end

      def delete(url, headers: {})
        request("DELETE", url, headers: headers)
      end

      def post(url, body: nil, headers: {})
        request("POST", url, body: body, headers: headers)
      end

      def put(url, body: nil, headers: {})
        request("PUT", url, body: body, headers: headers)
      end

      def patch(url, body: nil, headers: {})
        request("PATCH", url, body: body, headers: headers)
      end

      def request(method, url, body: nil, headers: {}, limit: nil)
        uri = URI.parse(url.to_s)
        verb = VERBS.fetch(method.to_s.upcase) { raise ArgumentError, "#{method} is not a method a transport sends" }

        unless origins.include?(Nonces.origin(uri))
          raise Foreign, "this transport holds tokens only for #{origins.join(', ')}"
        end

        held = tokens
        nonce = @nonces[uri] if held.bound?
        response = HTTP.deliver(signed(verb, uri, body, headers, held, nonce), limit: limit)

        return response unless held.bound?

        wanted = @nonces.learn(uri, response)

        return response unless wanted && wanted != nonce && nonce_asked?(response)

        HTTP.deliver(signed(verb, uri, body, headers, held, wanted), limit: limit)
      end

      def inspect
        "#<#{self.class.name} #{origins.join(', ')}>"
      end

      private

        def signed(verb, uri, body, headers, held, nonce)
          request = verb.new(uri, HTTP.default_headers.merge(headers))

          if held.bound?
            raise Error, "a DPoP token needs the key it is held to" if key.nil?

            request["Authorization"] = "#{Proof::SCHEME} #{held.access_token}"
            request["DPoP"] = key.proof(request.method, uri, access_token: held.access_token, nonce: nonce)
          else
            request["Authorization"] = "Bearer #{held.access_token}"
          end

          written(request, body)
        end

        def written(request, body)
          return request if body.nil?

          if body.is_a?(String)
            request.body = body
          else
            request.body = JSON.generate(body)
            request["Content-Type"] ||= "application/json"
          end

          request
        end

        def nonce_asked?(response)
          response.code.to_i == 401 && response["WWW-Authenticate"].to_s.include?("use_dpop_nonce")
        end
    end
  end
end
