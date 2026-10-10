module Masks
  module Server
    require "test_helper"

    class LockedOutTest < ActiveSupport::TestCase
      setup do
        @owner = create_actor(@tenant, nickname: "owner", scopes: "openid profile email masks:manage")
        within { @owner.reload.generate_backup_codes! }
      end

      test "nothing happens without MASKS_RECOVER" do
        assert_empty LockedOut.recover!(nil)
        assert within { @owner.reload.otp? }
      end

      test "the named account loses its second factors and gets a one-time password link" do
        said = LockedOut.recover!("#{@tenant.subdomain}/owner")

        assert_equal 1, said.size
        assert_match %r{/reset/\S+\z}, said.first

        owner = within { @owner.reload }
        refute owner.second_factor?
        refute owner.backup_codes?
        assert within { PasswordReset.redeem(said.first[%r{/reset/(\S+)\z}, 1]) }
        assert within { Event.where(action: Event::SECOND_FACTORS_RESET, actor: @owner, by: nil).exists? }
      end

      test "an account that does not exist is passed over" do
        assert_empty LockedOut.recover!("#{@tenant.subdomain}/nobody")
      end

      test "a tenant prefix keeps other tenants' accounts of the same name alone" do
        other = create_actor(other_tenant, nickname: "owner", scopes: "openid profile email masks:manage")

        LockedOut.recover!("#{@tenant.subdomain}/owner")

        assert within(other_tenant) { other.reload.otp? }
      end
    end
  end
end
