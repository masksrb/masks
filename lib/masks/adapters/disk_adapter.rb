module Masks
  module Adapters
    class DiskAdapter
      include Masks::Adapter

      setting :root,
              :string,
              env: "MASKS_STORAGE_DIR",
              default: -> { default_root }

      def setup?
        super && Dir.exist?(root)
      end

      def default_root
        defined?(Rails) ? Rails.root.join("storage").to_s : nil
      end

      def storage_service
        "Disk"
      end
    end
  end
end
