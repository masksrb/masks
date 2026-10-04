module Masks
  module Server
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
          @document ||= ::Rails.cache.fetch([ "resource_metadata", @resource ], expires_in: TTL, skip_nil: true) do
            candidates.lazy.filter_map { |url| fetch(url) }.first
          end || {}
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

          body = Outbound.fetch!(uri, open: OPEN_TIMEOUT, read: READ_TIMEOUT, ceiling: LIMIT,
                                      headers: { "Accept" => "application/json" })

          parsed = JSON.parse(body)
          parsed.is_a?(Hash) ? parsed : nil
        rescue StandardError
          nil
        end
    end
  end
end
