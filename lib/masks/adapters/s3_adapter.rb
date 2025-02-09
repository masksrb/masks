module Masks
  module Adapters
    class S3Adapter
      include Masks::Adapter

      setting :access_key_id, :string, env: "MASKS_S3_ACCESS_KEY_ID"
      setting :secret_access_key, :string, env: "MASKS_S3_SECRET_ACCESS_KEY"
      setting :region, :string, env: "MASKS_S3_REGION"
      setting :bucket, :string, env: "MASKS_S3_BUCKET"

      def storage_service
        "S3"
      end
    end
  end
end
