module Masks
  module Server
    require "test_helper"

    class RefreshGroupsJobTest < ActiveSupport::TestCase
      def rule_group(tenant = @tenant)
        within(tenant) do
          Group.create!(key: "staff", name: "Staff", source: "rule", rule: [ { "kind" => "email_domain", "value" => "example.com" } ])
        end
      end

      def member_nicknames(tenant = @tenant)
        within(tenant) { Group.find_by!(key: "staff").actors.pluck(:nickname).sort }
      end

      test "the hourly run fills a rule group with people a callback missed" do
        group = rule_group

        within do
          ada = Actor.create!(nickname: "ada", email: "ada@example.com", email_verified_at: Time.current)
          gone = Actor.create!(nickname: "gone", email: "gone@example.com", email_verified_at: Time.current)

          group.members.where(actor: ada).delete_all
          gone.update_columns(email: "gone@example.org")
          Event.where(action: Event::GROUP_JOINED).delete_all
        end

        RefreshGroupsJob.perform_now

        assert_equal %w[ada], member_nicknames

        refreshed = within { Event.where(action: Event::GROUP_REFRESHED).sole }
        assert_equal({ "group" => "staff", "source" => "rule", "added" => 1, "removed" => 1 }, refreshed.details.slice("group", "source", "added", "removed"))
      end

      test "a run that changes nothing records nothing" do
        rule_group

        RefreshGroupsJob.perform_now
        RefreshGroupsJob.perform_now

        assert_empty within { Event.where(action: Event::GROUP_REFRESHED) }
      end

      test "the run carries on past a tenant that raises and records which one" do
        broken = other_tenant
        rule_group
        rule_group(broken)
        within { Actor.create!(nickname: "ada", email: "ada@example.com", email_verified_at: Time.current) }
        within { Group.find_by!(key: "staff").members.delete_all }

        job = RefreshGroupsJob.new
        job.define_singleton_method(:refresh) do
          raise "the groups table is locked" if Current.tenant.id == broken.id

          super()
        end

        error = assert_raises(ApplicationJob::Incomplete) { job.perform_now }

        assert_match broken.subdomain, error.message
        assert_equal %w[ada], member_nicknames
        assert_equal 1, within(broken) { Event.where(action: Event::JOB_FAILED).count }
        assert_equal [ broken.subdomain ], JobFailures.last(RefreshGroupsJob.name)
      end
    end
  end
end
