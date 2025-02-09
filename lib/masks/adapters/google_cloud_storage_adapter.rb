module Masks
  module Adapters
    class GoogleCloudStorageAdapter
      include Masks::Adapter

      setting :project, :string, env: "MASKS_GCS_PROJECT"
      setting :credentials, :string, env: "MASKS_GCS_CREDENTIALS"
      setting :bucket, :string, env: "MASKS_GCS_BUCKET"

      def storage_service
        "GCS"
      end
    end
  end
end
