require "stringio"

module Masks
  module Client
    class Embedded
      LOOPBACK = "127.0.0.1".freeze
      DROPPED = %w[host accept-encoding connection content-length].freeze

      attr_reader :app

      def initialize(app, &serves)
        raise ArgumentError, "an embedded issuer needs the app that serves it" if app.nil?
        raise ArgumentError, "an embedded issuer needs a block naming the URLs it serves" if serves.nil?

        @app = app
        @serves = serves
      end

      def serves?(uri)
        @serves.call(uri) ? true : false
      end

      def deliver(request, limit: nil)
        uri = request.uri
        status, headers, body = answer(environment(request, uri), uri, limit)

        parsed(request, raw(status, headers, body))
      end

      def inspect
        "#<#{self.class.name} #{app.inspect}>"
      end

      private

        def answer(env, uri, limit)
          worker = Thread.new { collected(*app.call(env), uri, limit) }
          worker.report_on_exception = false

          unless worker.join(HTTP::READ_TIMEOUT)
            worker.kill
            raise Unreachable, Masks::Client.saying("unreachable", uri.host)
          end

          worker.value
        rescue Error
          raise
        rescue StandardError => e
          raise Unreachable, Masks::Client.saying("unreachable", uri.host)
        end

        def collected(status, headers, body, uri, limit)
          held = "".b

          body.each do |chunk|
            held << chunk.to_s.b
            raise Error, "#{uri.host} answered with more than #{limit} bytes" if limit && held.bytesize > limit
          end

          [ status.to_i, headers, held ]
        ensure
          body.close if body.respond_to?(:close)
        end

        def environment(request, uri)
          input = request.body.to_s.b

          env = {
            "REQUEST_METHOD" => request.method,
            "SCRIPT_NAME" => "",
            "PATH_INFO" => uri.path.to_s.empty? ? "/" : uri.path,
            "QUERY_STRING" => uri.query.to_s,
            "SERVER_NAME" => uri.host,
            "SERVER_PORT" => uri.port.to_s,
            "SERVER_PROTOCOL" => "HTTP/1.1",
            "REMOTE_ADDR" => LOOPBACK,
            "HTTP_HOST" => Nonces.origin(uri).delete_prefix("#{uri.scheme}://"),
            "HTTPS" => uri.scheme == "https" ? "on" : "off",
            "rack.url_scheme" => uri.scheme,
            "rack.input" => StringIO.new(input),
            "rack.errors" => $stderr
          }

          env["CONTENT_LENGTH"] = input.bytesize.to_s unless input.empty?

          request.each_header do |name, value|
            next if DROPPED.include?(name)

            key = name.upcase.tr("-", "_")
            env[key == "CONTENT_TYPE" ? key : "HTTP_#{key}"] = value
          end

          env
        end

        def raw(status, headers, body)
          lines = [ "HTTP/1.1 #{status} #{reason(status)}" ]

          headers.each do |name, value|
            next if %w[content-length transfer-encoding].include?(name.to_s.downcase)

            Array(value).flat_map { |held| held.to_s.split(/\r?\n/) }.each { |held| lines << "#{name}: #{held}" }
          end

          lines << "content-length: #{body.bytesize}"

          "#{lines.join("\r\n")}\r\n\r\n".b + body
        end

        def parsed(request, raw)
          io = Net::BufferedIO.new(StringIO.new(raw))
          response = Net::HTTPResponse.read_new(io)
          response.uri = request.uri
          response.reading_body(io, request.response_body_permitted?) { response.body }
          response
        end

        def reason(status)
          named = Net::HTTPResponse::CODE_TO_OBJ[status.to_s]

          named ? named.name.delete_prefix("Net::HTTP").gsub(/(?<=[a-z])(?=[A-Z])/, " ") : "Unknown"
        end
    end
  end
end
