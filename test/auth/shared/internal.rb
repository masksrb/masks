module Auth
  module Shared
    module Internal
      extend ActiveSupport::Concern

      included do
        describe "Internals" do
          test "internal tokens are stored in session for internal clients" do
            assert_login log_in("manager")

            if client.internal?
              assert_session Masks::InternalToken.first.secret,
                             [
                               *masks_session.device.full_path,
                               "internal_token",
                               client.key,
                               "token",
                             ]
            else
              assert_equal 0, Masks::InternalToken.count
            end
          end
        end
      end
    end
  end
end
