class ClientLogo < ApplicationRecord
  include TenantScoped

  class Unreachable < StandardError; end

  STORED = 256
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5

  belongs_to :client

  validates :client_id, uniqueness: { scope: :tenant_id }

  class << self
    def fetch!(client)
      source = client.logo_uri

      return where(client_id: client.id).delete_all if source.blank?

      bytes = download(source)

      raise Pictures::Unreadable, "a logo has to be an image" if Pictures.sniff(bytes).nil?

      square = Pictures.square(bytes, STORED)
      held = find_or_initialize_by(client_id: client.id)

      held.update!(
        source_uri: source,
        content_type: Pictures::CONTENT_TYPE,
        digest: Pictures.digest(square),
        byte_size: square.bytesize,
        data: square
      )

      held
    end

    private

      def download(source)
        uri = URI.parse(source)
        address = Rails.env.local? ? nil : Outbound.vetted(uri)

        raise Unreachable, "#{uri.host} resolves to an address this server will not call" if address.nil? && !Rails.env.local?

        response = Outbound.get(uri, open: OPEN_TIMEOUT, read: READ_TIMEOUT, address: address)

        raise Unreachable, "#{uri.host} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        raise Pictures::Unreadable, "a logo has to be smaller than #{Outbound::CEILING / 1.kilobyte}KB" if response.body.to_s.bytesize >= Outbound::CEILING

        response.body.to_s.b
      rescue URI::InvalidURIError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise Unreachable, e.message
      end
  end

  def resized(size)
    Pictures.resized(data, digest, size, stored: STORED, kind: "client-logo")
  end
end
