require "test_helper"

module Masks
  class Session
    class SessionTestCase < MasksTestCase
      def assert_session(value, keys)
        if value
          assert_equal(value, masks_session.data.dig(*keys))
        else
          assert_not masks_session.data.dig(*keys)
        end
      end

      def rails_session
        @rails_session ||= {}
      end

      def masks_env
        @masks_env ||= new_request!
      end

      def new_request!
        @masks_env = make_env.tap { |env| structure(Masks::Session.env(env)) }
      end

      def masks_session
        masks_env["masks.session"]
      end

      def structure(s)
        nil
      end
    end
  end
end
