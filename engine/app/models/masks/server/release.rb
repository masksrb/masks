module Masks
  module Server
    module Release
      URL = "https://api.github.com/repos/masksrb/masks/releases?per_page=20".freeze
      KEY = "masks:release".freeze
      KEEP = 3.days
      TAG = /\Aserver-v(\d+\.\d+\.\d+)\z/
      OPERATOR = /^\s*Operator:/i
      TIMEOUT = 5
      CEILING = 1.megabyte
      UNREADABLE = [ Outbound::Refused, JSON::ParserError, TypeError, NoMethodError ].freeze

      module_function

      def check!
        found = fetch

        return nil if found.nil?

        was = latest
        remember!(found)

        found if newer?(found["version"]) && was&.dig("version") != found["version"]
      end

      def fetch
        headers = { "Accept" => "application/vnd.github+json", "User-Agent" => "masks-server/#{VERSION}" }
        body = Outbound.get!(URI(URL), open: TIMEOUT, read: TIMEOUT, within: TIMEOUT, ceiling: CEILING, headers: headers).body

        JSON.parse(body).each do |release|
          version = release["tag_name"].to_s[TAG, 1]

          next if version.nil? || release["draft"] || release["prerelease"]

          return {
            "version" => version,
            "url" => release["html_url"].to_s,
            "operator_step" => release["body"].to_s.match?(OPERATOR),
            "checked_at" => Time.current.utc.iso8601
          }
        end

        nil
      rescue *UNREADABLE => error
        ::Rails.logger.warn("the release check could not read the releases: #{error.class}")
        nil
      end

      def remember!(found)
        ::Rails.cache.write(KEY, found, expires_in: KEEP)
      end

      def forget!
        ::Rails.cache.delete(KEY)
      end

      def latest
        ::Rails.cache.read(KEY)
      end

      def available
        found = latest

        found if found && newer?(found["version"])
      end

      def newer?(version)
        Gem::Version.new(version) > Gem::Version.new(VERSION)
      rescue ArgumentError
        false
      end
    end
  end
end
