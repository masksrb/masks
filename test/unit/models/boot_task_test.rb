module Masks
  module Server
    require "test_helper"

    class BootTaskTest < ActiveSupport::TestCase
      def task_name
        "test-#{SecureRandom.hex(4)}"
      end

      test "the first run does the task and the second run with the same input skips it" do
        task = task_name
        runs = 0

        first = BootTask.once(task, fingerprint: "ada") { runs += 1; "reset link" }
        second = BootTask.once(task, fingerprint: "ada") { runs += 1; "another link" }

        assert first.done?
        assert_equal "reset link", first.value
        assert_equal Socket.gethostname, first.host
        refute second.done?
        assert_equal Socket.gethostname, second.host
        assert_nil second.value
        assert_equal 1, runs
      end

      test "a different input runs the task again" do
        task = task_name
        runs = 0

        BootTask.once(task, fingerprint: "ada") { runs += 1 }
        BootTask.once(task, fingerprint: "grace") { runs += 1 }

        assert_equal 2, runs
      end

      test "a task that raises leaves nothing recorded, so the next replica tries" do
        task = task_name
        runs = 0

        assert_raises(RuntimeError) { BootTask.once(task, fingerprint: "ada") { raise "no database" } }

        BootTask.once(task, fingerprint: "ada") { runs += 1 }

        assert_equal 1, runs
      end

      test "each task holds its own lock while it runs" do
        task = task_name
        held = nil

        BootTask.once(task, fingerprint: "ada") do
          held = ActiveRecord::Base.connection.select_value(
            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND objid = #{BootTask.lock_id(task)}"
          )
        end

        assert_equal 1, held
      end
    end
  end
end
