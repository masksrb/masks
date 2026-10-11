module Masks
  module Server
    require "test_helper"

    class MasterKeyTest < ActiveSupport::TestCase
      OLD = Array(ActiveRecord::Encryption.config.primary_key).last
      NEW = "a-new-master-key-derived-primary-key".freeze

      def keyed(*keys, &block)
        provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new(keys)

        ActiveRecord::Encryption.with_encryption_context(key_provider: provider, &block)
      end

      setup do
        keyed(OLD) do
          @tenant.update!(pairwise_salt: "a salt")
          @tenant.ensure_signing_key!
          @actor = create_actor(@tenant, nickname: "ada")
          within { @actor.update!(otp_secret: "JBSWY3DPEHPK3PXP", otp_enabled_at: Time.current) }
        end
      end

      test "a key that matches the database passes the check" do
        keyed(OLD) { MasterKey.check! }
      end

      test "a key that does not match the database stops the server and says why" do
        error = assert_raises(MasterKey::Mismatch) { keyed(NEW) { MasterKey.check! } }

        assert_match "MASKS_MASTER_KEY", error.message
      end

      test "re-encrypting with the previous key held moves every encrypted column to the new key" do
        keyed(OLD, NEW) { MasterKey.reencrypt! }

        keyed(NEW) do
          MasterKey.check!

          assert_empty MasterKey.underived

          assert_equal "a salt", Tenant.find(@tenant.id).pairwise_salt
          assert_equal "JBSWY3DPEHPK3PXP", within { Actor.find(@actor.id).otp_secret }
          assert within { SigningKey.first.private_pem.start_with?("-----BEGIN") }
        end
      end

      test "a key that matches the database passes the check when its rows are still under the shared key" do
        legacy = keyed(OLD) do
          ActiveRecord::Encryption.encryptor.encrypt("a salt", key_provider: ActiveRecord::Encryption.key_provider)
        end
        Tenant.where(id: @tenant.id).update_all([ "pairwise_salt = ?", legacy ])

        keyed(OLD) { MasterKey.check! }
        assert_raises(MasterKey::Mismatch) { keyed(NEW) { MasterKey.check! } }
      end

      test "every model with an encrypted column is re-encrypted" do
        names = MasterKey.encrypted_models.map(&:name)

        %w[Actor SigningKey Connection Provider Adapter EventStream SignalStream].each do |name|
          assert_includes names, "Masks::Server::#{name}"
        end
      end
    end
  end
end
