module Masks
  class Env < RecursiveOpenStruct
    PRIMARY_DB_TYPE = "primary"
    DEFAULT_DB_ADAPTER = "sqlite3"

    def debug?
      Rails.env.development?
    rescue StandardError
      false
    end

    def installer
      cls = (self[:mode] || "client")
      cls = "Masks::Installations::#{cls.classify}" unless cls.include?("::")
      cls.constantize
    rescue => e
      byebug
    end

    def secrets
      @secrets ||= Shims::RailsSecrets.new(self)
    end

    def rack(method, path, query, session: nil)
      base = {
        "REQUEST_METHOD" => method.to_s.upcase,
        "PATH_INFO" => path,
        "QUERY_STRING" => query.to_query,
        "rack.session" => session,
      }

      base
    end

    def prompts
      self[:prompts]&.map(&:constantize)
    end

    def providers
      self[:providers]&.map(&:constantize)
    end

    def db_enabled?(type)
      return true if type.to_s == PRIMARY_DB_TYPE

      db[type]&.url&.present? || db[type]&.adapter&.present?
    end

    def multiple_dbs?
      %w[queue cache sessions websockets].any? { |type| db_enabled?(type) }
    end

    def db_pool(type)
      return unless db_enabled?(type)

      ((workers || 1) * (threads || 1)) + 2
    end

    def db_adapter(type)
      return unless db_enabled?(type)

      config = primary_type?(type) ? db : db[type]
      adapter = config&.adapter&.presence
      adapter ||= adapter_from_url(config&.url)
      adapter ||= DEFAULT_DB_ADAPTER
      adapter
    end

    def db_name(type)
      return unless db_enabled?(type)

      config = primary_type?(type) ? db : db[type]

      return config.name if config.name&.present?

      env = Rails.env.production? ? nil : Rails.env
      name = primary_type?(type) ? "masks" : type
      root = ENV.fetch("MASKS_DATA_DIR", "data/").chomp("/")

      if db_adapter(type) == "sqlite3"
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

    def primary_type?(type)
      type.to_s == PRIMARY_DB_TYPE
    end
  end
end
