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
          Tenant.find_each(&:encrypt)

          Tenant.find_each do |tenant|
            Tenant.switch(tenant) { encrypted_models.each { |model| model.unscoped.find_each(&:encrypt) } }
          end
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
