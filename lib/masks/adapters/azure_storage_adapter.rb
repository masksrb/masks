module Masks
  module Adapters
    class AzureStorageAdapter
      include Masks::Adapter

      setting :storage_account_name,
              :string,
              env: "MASKS_AZURE_STORAGE_ACCOUNT_NAME"
      setting :storage_access_key,
              :string,
              env: "MASKS_AZURE_STORAGE_ACCESS_KEY"
      setting :container, :string, env: "MASKS_AZURE_STORAGE_CONTAINER"

      def storage_service
        "AzureStorage"
      end
    end
  end
end
