module Masks
  module Server
    require "test_helper"

    class TenantKeyProviderTest < ActiveSupport::TestCase
      SECRET = "JBSWY3DPEHPK3PXP".freeze

      setup do
        @actor = create_actor(@tenant, nickname: "ada")
        within { @actor.update!(otp_secret: SECRET, otp_enabled_at: Time.current) }
      end

      def stored(actor = @actor)
        within { Actor.find(actor.id).ciphertext_for(:otp_secret) }
      end

      def otp_type
        Actor.type_for_attribute(:otp_secret)
      end

      def shared_only(ciphertext)
        ActiveRecord::Encryption.encryptor.decrypt(ciphertext, key_provider: ActiveRecord::Encryption.key_provider)
      end

      test "a secret encrypted in one tenant reads back in that tenant" do
        assert_equal SECRET, within { otp_type.deserialize(stored) }
      end

      test "a secret encrypted in one tenant cannot be read while switched to another" do
        ciphertext = stored

        assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
          within(other_tenant) { otp_type.deserialize(ciphertext) }
        end
      end

      test "a tenant's secrets are not encrypted under the shared key" do
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) { shared_only(stored) }
      end

      test "two tenants holding the same secret store different ciphertexts under different keys" do
        theirs = create_actor(other_tenant, nickname: "bo")
        within(other_tenant) { theirs.update!(otp_secret: SECRET, otp_enabled_at: Time.current) }
        ciphertext = within(other_tenant) { Actor.find(theirs.id).ciphertext_for(:otp_secret) }

        assert_raises(ActiveRecord::Encryption::Errors::Decryption) { within { otp_type.deserialize(ciphertext) } }
      end

      test "encrypting a tenant's record outside any tenant raises" do
        assert_nil Current.tenant

        assert_raises(TenantKeyProvider::NoTenant) { otp_type.serialize(SECRET) }
      end

      test "reading a tenant's secret outside any tenant raises" do
        ciphertext = stored

        assert_raises(TenantKeyProvider::NoTenant) { otp_type.deserialize(ciphertext) }
      end

      test "a tenant's own columns use that tenant's key wherever they are read" do
        @tenant.update!(pairwise_salt: "a salt")
        ciphertext = Tenant.find(@tenant.id).ciphertext_for(:pairwise_salt)

        assert_equal "a salt", within(other_tenant) { Tenant.find(@tenant.id).pairwise_salt }
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) { shared_only(ciphertext) }
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
          TenantKeyProvider.keyed(other_tenant) { Tenant.type_for_attribute(:pairwise_salt).deserialize(ciphertext) }
        end
      end

      test "a row encrypted under the shared key still reads, and re-encrypting moves it to the tenant's key" do
        legacy = ActiveRecord::Encryption.encryptor.encrypt(SECRET, key_provider: ActiveRecord::Encryption.key_provider)
        within { Actor.where(id: @actor.id).update_all([ "otp_secret = ?", legacy ]) }
        Tenant.where(id: @tenant.id).update_all([ "pairwise_salt = ?, keys_derived_at = NULL", legacy ])

        assert_equal SECRET, within { Actor.find(@actor.id).otp_secret }
        assert_equal SECRET, Tenant.find(@tenant.id).pairwise_salt
        assert_equal [ @tenant.id ], MasterKey.underived.ids

        MasterKey.reencrypt!(MasterKey.underived)

        assert_empty MasterKey.underived
        assert_equal SECRET, within { Actor.find(@actor.id).otp_secret }
        assert_equal SECRET, Tenant.find(@tenant.id).pairwise_salt
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) { shared_only(stored) }
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
          shared_only(Tenant.find(@tenant.id).ciphertext_for(:pairwise_salt))
        end
      end

      test "a tenant created under tenant keys has nothing to re-encrypt" do
        assert_empty MasterKey.underived
      end
    end
  end
end
