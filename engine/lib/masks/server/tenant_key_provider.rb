require "openssl"

module Masks
  module Server
    class TenantKeyProvider
      class NoTenant < StandardError
        def initialize(message = "a tenant's encrypted column was read or written outside that tenant. Each tenant's " \
                                 "secrets are encrypted under a key of its own, so switch to the tenant first.")
          super
        end
      end

      LABEL = "masks/encryption/tenant/".freeze
      KEYED = :masks_keyed_tenant

      class << self
        def keyed(tenant)
          held = ActiveSupport::IsolatedExecutionState[KEYED]
          ActiveSupport::IsolatedExecutionState[KEYED] = tenant

          begin
            yield
          ensure
            ActiveSupport::IsolatedExecutionState[KEYED] = held
          end
        end

        def tenant
          ActiveSupport::IsolatedExecutionState[KEYED] || Current.tenant
        end
      end

      def initialize(shared = nil, keyed: false)
        @shared = shared
        @keyed = keyed
      end

      def shared
        @shared || ActiveRecord::Encryption.key_provider
      end

      def encryption_key
        derive(shared.encryption_key, tenant!)
      end

      def decryption_keys(message)
        tenant = tenant!
        held = Array(shared.decryption_keys(message)).reverse

        held.map { |key| derive(key, tenant) } + held
      end

      def tenant_keys(tenant)
        ActiveRecord::Encryption::KeyProvider.new(
          Array(shared.decryption_keys(ActiveRecord::Encryption::Message.new)).map { |key| derive(key, tenant) }
        )
      end

      private

        def tenant!
          tenant = @keyed ? self.class.tenant : Current.tenant
          raise NoTenant if tenant.nil? || tenant.uuid.blank?

          tenant
        end

        def derive(key, tenant)
          ActiveRecord::Encryption::Key.new(
            OpenSSL::KDF.hkdf(key.secret, salt: "", info: "#{LABEL}#{tenant.uuid}",
                                          length: ActiveRecord::Encryption.cipher.key_length, hash: "SHA256")
          )
        end
    end
  end
end
