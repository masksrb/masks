module RackOAuth2Endpoint
  extend ActiveSupport::Concern

  class Payload
    def initialize(payload)
      @payload = payload
    end

    def token_response
      @payload
    end
  end

  private

    def render_rack(triple)
      status, headers, body = triple

      content = +""
      body.each { |part| content << part }
      body.close if body.respond_to?(:close)

      location = headers["Location"] || headers["location"]

      return redirect_to(location, allow_other_host: true, status: status) if location

      headers.each do |key, value|
        next if %w[content-length content-type].include?(key.downcase)

        response.headers[key] = value
      end

      render plain: content,
             status: status,
             content_type: headers["Content-Type"] || headers["content-type"] || "application/json"
    end

    def repeated(name)
      Array(Rack::Utils.parse_query(request.raw_post)[name]).map(&:to_s).reject(&:empty?)
    end
end
