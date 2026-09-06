class ResourceMetadata
  WELL_KNOWN = "/.well-known/oauth-protected-resource".freeze
  LIMIT = 64 * 1024
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3
  LONGEST = 200
  TTL = 5.minutes

  class << self
    def describe(resources, scopes)
      published = Array(resources).reject(&:blank?).reduce({}) do |held, resource|
        new(resource).descriptions.merge(held)
      end

      Scopes.list(scopes).map do |scope|
        [ scope, published[scope].presence || Scopes.description_for(scope) ]
      end
    end
  end

  def initialize(resource)
    @resource = resource.to_s
  end

  def descriptions
    Localized.fields(document, "scope_descriptions").each_with_object({}) do |(scope, description), held|
      held[scope.to_s] = description.to_s.truncate(LONGEST)
    end
  end

  private

    def document
      @document ||= Rails.cache.fetch([ "resource_metadata", @resource ], expires_in: TTL) do
        candidates.lazy.filter_map { |url| fetch(url) }.first || {}
      end
    end

    def candidates
      uri = URI.parse(@resource)
      return [] if uri.host.blank?

      port = ":#{uri.port}" unless uri.port == uri.default_port
      origin = "#{uri.scheme}://#{uri.host}#{port}"

      [ "#{origin}#{WELL_KNOWN}#{uri.path.to_s.chomp('/')}", "#{origin}#{WELL_KNOWN}" ].uniq
    rescue URI::InvalidURIError
      []
    end

    def fetch(url)
      uri = URI.parse(url)

      response = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json")) }

      return nil unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body.to_s[0, LIMIT])
      parsed.is_a?(Hash) ? parsed : nil
    rescue StandardError
      nil
    end
end
