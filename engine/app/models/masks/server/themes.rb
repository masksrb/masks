module Masks
  module Server
    module Themes
      Theme = Data.define(:key, :digest, :body)

      LIMIT = 256.kilobytes

      class << self
        def for(tenant:, client: nil)
          return [] if tenant.nil?

          keys = [ tenant.subdomain ]
          keys << "#{tenant.subdomain}/#{client.client_id}" if client

          keys.filter_map { |key| catalog[key] }
        end

        def find(tenant:, digest:)
          return nil if tenant.nil?

          catalog.each_value.find do |theme|
            theme.digest == digest && owned_by?(theme, tenant)
          end
        end

        def catalog
          return scan if ::Rails.env.development?

          @catalog ||= scan
        end

        def reload!
          @catalog = scan
        end

        private

          def owned_by?(theme, tenant)
            theme.key == tenant.subdomain || theme.key.start_with?("#{tenant.subdomain}/")
          end

          def scan
            root = Pathname(::Rails.configuration.masks.themes_path.to_s)
            return {} unless root.directory?

            Dir.glob([ "*.css", "*/*.css" ], base: root).sort.each_with_object({}) do |relative, catalog|
              path = root.join(relative)
              next unless path.file?

              if path.size > LIMIT
                ::Rails.logger.warn("theme #{relative} is over #{LIMIT / 1.kilobyte} KB and is not served")
                next
              end

              body = path.binread
              key = relative.delete_suffix(".css")

              catalog[key] = Theme.new(key: key, digest: Digest::SHA256.hexdigest(body)[0, 32], body: body).freeze
            end.freeze
          end
      end
    end
  end
end
