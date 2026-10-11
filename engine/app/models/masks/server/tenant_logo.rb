module Masks
  module Server
    class TenantLogo < ApplicationRecord
      include TenantScoped

      STORED = 256
      LIMIT = 4.megabytes

      validates :tenant_id, uniqueness: true

      class << self
        def store!(tenant, upload)
          bytes = upload.respond_to?(:read) ? upload.read(LIMIT + 1).to_s.b : upload.to_s.b

          raise Pictures::Unreadable, "a logo has to be smaller than #{LIMIT / 1.megabyte}MB" if bytes.bytesize > LIMIT
          raise Pictures::Unreadable, "a logo has to be an image" if Pictures.sniff(bytes).nil?

          square = Pictures.square(bytes, STORED)
          digest = Pictures.digest(square)

          transaction do
            find_or_initialize_by(tenant_id: tenant.id).update!(
              content_type: Pictures::CONTENT_TYPE, digest: digest, byte_size: square.bytesize, data: square
            )
            tenant.update!(logo_digest: digest)
          end
        rescue ActiveRecord::RecordNotUnique
          retry
        end

        def forget!(tenant)
          transaction do
            where(tenant_id: tenant.id).delete_all
            tenant.update!(logo_digest: nil)
          end
        end
      end

      def resized(size)
        Pictures.resized(data, digest, size, stored: STORED, kind: "tenant-logo")
      end
    end
  end
end
