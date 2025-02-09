module Masks
  module Shims
    class RailsDatabase
      PRIMARY_DB_TYPE = "primary"
      DEFAULT_DB_ADAPTER = "sqlite3"

      attr_reader :conf

      def initialize(conf)
        @conf = conf
      end

      def enabled?(type = PRIMARY_DB_TYPE)
        return true if primary_type?(type)

        conf.setting("#{type}_db_url")
      end

      def multiple?
        %w[queue cache sessions websockets].any? { |type| enabled?(type) }
      end

      def pool
        ([1, conf.workers].max * conf.threads) + 2
      end

      def adapter(type = PRIMARY_DB_TYPE)
        return unless enabled?(type)

        adapter =
          if primary_type?(type)
            conf.db_adapter
          else
            conf.setting("#{type}_db_adapter")
          end

        adapter || adapter_from_url(url(type))
      end

      def url(type = PRIMARY_DB_TYPE)
        return unless enabled?(type)

        primary_type?(type) ? conf.db_url : conf.setting("#{type}_db_url")
      end

      def primary_type?(type = PRIMARY_DB_TYPE)
        type.to_s == PRIMARY_DB_TYPE
      end

      def name(type = PRIMARY_DB_TYPE)
        return unless enabled?(type)

        name =
          primary_type?(type) ? conf.db_name : conf.setting("#{type}_db_name")

        return name if name&.present?

        env = Rails.env.production? ? nil : Rails.env
        name = primary_type?(type) ? "masks" : type
        root = ENV.fetch("MASKS_DATA_DIR", "data/").chomp("/")

        if adapter(type) == "sqlite3"
          "#{root}/#{[env, name].compact.join(".").presence || "masks"}.sqlite3"
        else
          ["masks", name == "masks" ? env : ([env, name])].flatten.compact.join(
            "_",
          )
        end
      end

      private

      def adapter_from_url(value)
        return unless value&.present?

        value.start_with?("postgres") ? "postgresql" : "sqlite3"
      end
    end
  end
end
