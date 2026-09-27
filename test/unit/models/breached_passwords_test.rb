module Masks
  module Server
    require "test_helper"

    class BreachedPasswordsTest < ActiveSupport::TestCase
      def answering(body)
        held = Outbound.method(:fetch!)
        asked = []
        Outbound.define_singleton_method(:fetch!) do |uri, **|
          asked << uri.to_s
          body.is_a?(Exception) ? raise(body) : body
        end

        yield asked
      ensure
        Outbound.define_singleton_method(:fetch!, held)
      end

      test "only the first five characters of the hash leave, and a matching suffix is a breach" do
        digest = Digest::SHA1.hexdigest("hunter2").upcase

        answering("0000000000000000000000000000000000A:0\r\n#{digest[5..]}:17\r\n") do |asked|
          assert BreachedPasswords.breached?("hunter2")
          assert_equal [ "#{BreachedPasswords::RANGE_URL}#{digest[0, 5]}" ], asked
          refute_includes asked.first, "hunter2"
        end
      end

      test "a padded line with a zero count is not a breach" do
        digest = Digest::SHA1.hexdigest("hunter2").upcase

        answering("#{digest[5..]}:0\r\n") { refute BreachedPasswords.breached?("hunter2") }
      end

      test "an unreachable range service lets the password through" do
        answering(Outbound::Refused.new("down")) { refute BreachedPasswords.breached?("hunter2") }
      end
    end
  end
end
