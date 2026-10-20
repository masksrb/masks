module Masks
  module Server
    require "test_helper"

    class AcrossTenantsTest < ActiveSupport::TestCase
      def failures_for(tenant)
        within(tenant) { Event.where(action: Event::JOB_FAILED).order(:created_at).to_a }
      end

      test "key rotation carries on past a tenant that raises, records which one, and still raises at the end" do
        broken = other_tenant
        broken.update!(key_rotation_days: 30)
        @tenant.update!(key_rotation_days: 30)
        first = within { SigningKey.active.first }

        job = RotateSigningKeysJob.new
        job.define_singleton_method(:advance) do |tenant|
          raise "the key store is gone" if tenant.id == broken.id

          super(tenant)
        end

        travel(29.days + 1.hour) do
          error = assert_raises(ApplicationJob::Incomplete) { job.perform_now }

          assert_match broken.subdomain, error.message
        end

        assert within { SigningKey.staged.first }, "the healthy tenant was still rotated"
        assert_equal first.kid, within { SigningKey.active.first.kid }

        failed = failures_for(broken)
        assert_equal 1, failed.size
        assert_equal "RotateSigningKeysJob", failed.first.details["job"]
        assert_equal "RuntimeError", failed.first.details["error"]
        assert_empty failures_for(@tenant)
        assert_equal [ broken.subdomain ], JobFailures.last(RotateSigningKeysJob.name)
      end

      test "a run with no failures clears the tenants recorded from the run before" do
        JobFailures.record(CheckDomainClaimsJob.name, [ "acme" ])

        CheckDomainClaimsJob.perform_now

        assert_empty JobFailures.last(CheckDomainClaimsJob.name)
      end

      test "domain checks carry on past a tenant that raises" do
        broken = other_tenant
        seen = []

        job = CheckDomainClaimsJob.new
        job.define_singleton_method(:check) do
          raise "dns is down" if Current.tenant.id == broken.id

          seen << Current.tenant.subdomain
          super()
        end

        assert_raises(ApplicationJob::Incomplete) { job.perform_now }

        assert_includes seen, @tenant.subdomain
        assert_equal 1, failures_for(broken).size
        assert_equal [ broken.subdomain ], JobFailures.last(CheckDomainClaimsJob.name)
      end

      test "saml metadata refresh carries on past a tenant that raises" do
        broken = other_tenant
        seen = []

        job = RefreshSamlMetadataJob.new
        job.define_singleton_method(:refresh) do
          raise "the metadata table is locked" if Current.tenant.id == broken.id

          seen << Current.tenant.subdomain
          super()
        end

        assert_raises(ApplicationJob::Incomplete) { job.perform_now }

        assert_includes seen, @tenant.subdomain
        assert_equal 1, failures_for(broken).size
      end

      test "idle account sweeps carry on past a tenant that raises" do
        broken = other_tenant
        broken.update!(suspend_after: 365)
        @tenant.update!(suspend_after: 365)
        seen = []
        held = IdleAccounts.method(:sweep)

        IdleAccounts.define_singleton_method(:sweep) do |tenant|
          raise "no mail" if tenant.id == broken.id

          seen << tenant.subdomain
          held.call(tenant)
        end

        assert_raises(ApplicationJob::Incomplete) { IdleAccountsJob.perform_now }

        assert_includes seen, @tenant.subdomain
        assert_equal 1, failures_for(broken).size
      ensure
        IdleAccounts.define_singleton_method(:sweep, held) if held
      end
    end
  end
end
