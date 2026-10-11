module Masks
  module Server
    module MasterKey
      class Mismatch < StandardError; end

      class << self
        def check!
          Tenant.active.find_each do |tenant|
            tenant.pairwise_salt
            Tenant.switch(tenant) { SigningKey.find_each(&:private_pem) }
          end
        rescue ActiveRecord::Encryption::Errors::Decryption
          raise Mismatch, "this server's encryption key cannot read the database's encrypted columns. Every " \
                          "replica needs the same MASKS_MASTER_KEY, a restored database needs the key it was " \
                          "backed up with, and a rotated key needs MASKS_PREVIOUS_MASTER_KEY until it is re-encrypted."
        end

        def reencrypt!
          Tenant.find_each do |tenant|
            Tenant.switch(tenant) do
              Tenant.transaction do
                encrypted_models.each { |model| model.unscoped.find_each(&:encrypt) }
                tenant.encrypt
              end
            end
          end
        end

        def shared?
          Tenant.find_each.any? do |tenant|
            keys = Server.key_provider.tenant_keys(tenant)

            Tenant.switch(tenant) do
              shared_in?(Tenant.where(id: tenant.id), keys) ||
                encrypted_models.any? { |model| shared_in?(model.unscoped, keys) }
            end
          end
        end

        def encrypted_models
          ::Rails.application.eager_load!

          ApplicationRecord.descendants.select do |model|
            model.base_class == model && model != Tenant && model.encrypted_attributes.present?
          end
        end

        private

          def shared_in?(scope, keys)
            connection = scope.connection
            columns = scope.klass.encrypted_attributes.map { |name| connection.quote_column_name(name) }
            held = scope.where(columns.map { |column| "#{column} IS NOT NULL" }.join(" OR "))

            held.in_batches(of: 1000).any? do |batch|
              connection.select_rows(batch.select(Arel.sql(columns.join(", "))).to_sql).flatten.compact.any? do |value|
                ActiveRecord::Encryption.encryptor.decrypt(value, key_provider: keys)
                false
              rescue ActiveRecord::Encryption::Errors::Decryption
                true
              end
            end
          end
      end
    end
  end
end
