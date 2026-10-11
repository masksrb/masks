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

        def reencrypt!(tenants = Tenant.all)
          tenants.find_each do |tenant|
            Tenant.switch(tenant) do
              Tenant.transaction do
                encrypted_models.each { |model| model.unscoped.find_each(&:encrypt) }
                tenant.encrypt
                tenant.update_columns(keys_derived_at: Time.current)
              end
            end
          end
        end

        def underived
          Tenant.where(keys_derived_at: nil)
        end

        def encrypted_models
          ::Rails.application.eager_load!

          ApplicationRecord.descendants.select do |model|
            model.base_class == model && model != Tenant && model.encrypted_attributes.present?
          end
        end
      end
    end
  end
end
