module Masks
  module Server
    require "test_helper"

    class ConfirmationCodeTest < ActiveSupport::TestCase
      setup do
        @actor = create_actor(@tenant)
      end

      def open
        within { ConfirmationCode.open!(actor: @actor, channel: ConfirmationCode::EMAIL, address: "owner@example.com") }
      end

      test "a wrong guess read before the right one landed does not bring a used code back" do
        token, code = open
        stale = within { ConfirmationCode.find(token.id) }

        assert within { token.verify(code) }
        assert_not within { stale.verify("000000" == code ? "111111" : "000000") }

        assert within { token.reload.consumed? }
      end

      test "the right code is refused once it has been used, however stale the copy holding it" do
        token, code = open
        stale = within { ConfirmationCode.find(token.id) }

        assert within { token.verify(code) }
        assert_not within { stale.verify(code) }
      end

      test "guesses made from copies read at the same moment still count against the cap" do
        token, code = open
        wrong = code == "000000" ? "111111" : "000000"
        copies = within { Array.new(ConfirmationCode::ATTEMPTS) { ConfirmationCode.find(token.id) } }

        copies.each { |copy| within { copy.verify(wrong) } }

        assert within { token.reload.consumed? }
        assert_not within { ConfirmationCode.find(token.id).verify(code) }
      end
    end
  end
end
