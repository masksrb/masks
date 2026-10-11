module Masks
  module Server
    module Forwarded
      class << self
        def origin(value)
          uri = value.is_a?(URI::Generic) ? value : URI.parse(value.to_s)
          return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

          port = ":#{uri.port}" unless uri.port == uri.default_port
          "#{uri.scheme}://#{uri.host.downcase}#{port}"
        rescue URI::InvalidURIError
          nil
        end

        def target(request)
          held = request.env[ForwardedApp::KEY] || {}
          original = held["HTTP_X_ORIGINAL_URL"].presence
          return parse(original) if original

          host = held["HTTP_X_FORWARDED_HOST"].to_s.split(",").first.to_s.strip
          return nil if host.empty?

          scheme = request.headers["X-Forwarded-Proto"].to_s.split(",").first.to_s.strip.presence || "https"
          path = held["HTTP_X_FORWARDED_URI"].presence || "/"

          parse("#{scheme}://#{host}#{path}")
        end

        private

          def parse(value)
            uri = URI.parse(value)
            uri if uri.is_a?(URI::HTTP) && uri.host.present?
          rescue URI::InvalidURIError
            nil
          end
      end
    end
  end
end
