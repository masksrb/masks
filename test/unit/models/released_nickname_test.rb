module Masks
  module Server
    require "test_helper"

    class ReleasedNicknameTest < ActiveSupport::TestCase
      setup do
        @ada = create_actor(@tenant, nickname: "ada", email: "ada@example.com")
        @grace = create_actor(@tenant, nickname: "grace", email: "grace@example.com")
      end

      test "a nickname given up by a rename is held" do
        within(@tenant) do
          @ada.update!(nickname: "countess")

          assert ReleasedNickname.holding("ada").exists?
          assert ReleasedNickname.holding("ADA").exists?
          assert ReleasedNickname.held_from?("ada", @grace)
          refute ReleasedNickname.held_from?("ada", @ada)
        end
      end

      test "somebody else cannot take a held nickname" do
        within(@tenant) do
          @ada.update!(nickname: "countess")
          @grace.nickname = "Ada"

          refute @grace.valid?
          assert_includes @grace.errors.full_messages.to_sentence, "given up recently"
        end
      end

      test "a new account cannot take a held nickname either" do
        within(@tenant) do
          @ada.update!(nickname: "countess")

          assert_raises(ActiveRecord::RecordInvalid) { create_actor(@tenant, nickname: "ada", email: "new@example.com") }
        end
      end

      test "the one who gave a nickname up can take it back" do
        within(@tenant) do
          @ada.update!(nickname: "countess")
          @ada.update!(nickname: "ada")

          assert_equal "ada", @ada.reload.nickname
          refute ReleasedNickname.holding("ada").exists?
          assert ReleasedNickname.holding("countess").exists?
        end
      end

      test "the hold lapses after thirty days" do
        within(@tenant) do
          @ada.update!(nickname: "countess")

          travel ReleasedNickname::HOLD + 1.minute do
            refute ReleasedNickname.held_from?("ada", @grace)
            assert @grace.update(nickname: "ada")
          end
        end
      end

      test "deleting an account holds its nickname for everybody" do
        within(@tenant) do
          @ada.destroy!

          assert ReleasedNickname.held_from?("ada", @grace)
          refute @grace.update(nickname: "ada")
        end
      end

      test "a trusted rename ignores the hold" do
        within(@tenant) do
          @ada.update!(nickname: "countess")
          @grace.trusted_rename = true

          assert @grace.update(nickname: "ada")
        end
      end

      test "cleanup sweeps holds that have lapsed" do
        within(@tenant) do
          @ada.update!(nickname: "countess")
          @grace.update!(nickname: "admiral")
          ReleasedNickname.find_by(nickname: "grace").update!(released_at: (ReleasedNickname::HOLD + 1.day).ago)
        end

        CleanupJob.perform_now

        within(@tenant) do
          assert ReleasedNickname.exists?(nickname: "ada")
          refute ReleasedNickname.exists?(nickname: "grace")
        end
      end
    end
  end
end
