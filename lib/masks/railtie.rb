module Masks
  class Railtie < Rails::Railtie
    initializer "masks.routing" do |app|
      Masks::Routing.install!

      app.middleware.use Masks::Routing::Middleware
    end

    config.before_configuration do
      use_secrets if Masks.conf.use_secrets
      use_sessions if Masks.conf.use_sessions
    end

    def use_secrets
      masks = Masks.conf.rails_secrets
      config = Rails.application.config
      config.secret_key_base = masks.secret_key
      config.active_record.encryption.primary_key =
        masks.encryption_key&.presence
      config.active_record.encryption.deterministic_key =
        masks.deterministic_key&.presence
      config.active_record.encryption.key_derivation_salt = masks.salt&.presence
    end

    def use_sessions
      masks = Masks.conf
      config = Rails.application.config
      config.session_store :active_record_store, key: masks.session_cookie_name
      config.to_prepare do
        config.session_options[
          :expire_after
        ] = Masks::SessionRecord.expire_after if Masks::SessionRecord.expire_after

        ActionDispatch::Session::ActiveRecordStore.session_class =
          Masks::SessionRecord

        ActiveRecord::SessionStore::Session.table_name = "masks_sessions"
      rescue => e
        Rails.logger.warn("skipping session configuration...")
        nil
      end
    end
  end
end
