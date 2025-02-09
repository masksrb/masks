require "test_helper"

require_relative "session_test_case"

module Masks
  class Session
    class CheckTest < SessionTestCase
      def structure(session)
        session.structure do
          device

          current :test

          check :root
          check :check, parent: :test
          check :child, parent: :device
          check :child2, parent: :child
        end
      end

      test "checks with no underlying data do not raise a KeyError" do
        assert_not masks_session[:check]
      end

      test "checks can be added to the structure, checked, and interrogated" do
        assert_not masks_session[:root]

        masks_session[:root] = 1.minute.from_now

        assert_session true, %w[root checked]
      end

      test "session structure can be nested" do
        assert_not masks_session[:child]

        masks_session[:child] = 1.minute.from_now
        masks_session[:child2] = 1.minute.from_now

        assert_session true, [*masks_session.child.full_path, "checked"]
        assert_session true, [*masks_session.child2.full_path, "checked"]
      end
    end
  end
end
