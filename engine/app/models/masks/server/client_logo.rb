module Masks
  module Server
    class ClientLogo < ApplicationRecord
      include TenantScoped

      STORED = 256
      OPEN_TIMEOUT = 3
      READ_TIMEOUT = 5
      WITHIN = 15

      belongs_to :client

      validates :client_id, uniqueness: { scope: :tenant_id }

      class << self
        def fetch!(client)
          return forget(client) if client.logo_uri.blank?

          bytes = Outbound.fetch!(URI.parse(client.logo_uri), open: OPEN_TIMEOUT, read: READ_TIMEOUT, within: WITHIN)

          raise Pictures::Unreadable, "a logo has to be an image" if Pictures.sniff(bytes).nil?

          keep(client, Pictures.square(bytes, STORED))
        end

        def forget(client)
          transaction do
            where(client_id: client.id).delete_all
            client.update_column(:logo_digest, nil)
          end
        end

        private

          def keep(client, square)
            digest = Pictures.digest(square)

            transaction do
              find_or_initialize_by(client_id: client.id).update!(
                source_uri: client.logo_uri, content_type: Pictures::CONTENT_TYPE,
                digest: digest, byte_size: square.bytesize, data: square
              )
              client.update_column(:logo_digest, digest)
            end
          rescue ActiveRecord::RecordNotUnique
            retry
          end
      end

      def resized(size)
        Pictures.resized(data, digest, size, stored: STORED, kind: "client-logo")
      end
    end
  end
end
