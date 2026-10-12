module Masks
  module Server
    require "test_helper"
    require_relative "../../support/solves_work"

    class ProofOfWorkTest < ActiveSupport::TestCase
      include SolvesWork

      BITS = 8

      def issued(bits: BITS, bound_to: "login-a")
        ProofOfWork.issue(bits: bits, bound_to: bound_to)
      end

      def verify(work, counter, bits: BITS, bound_to: "login-a")
        within { ProofOfWork.verify(work, counter, bits: bits, bound_to: bound_to) }
      end

      test "a counter that gives enough leading zero bits is accepted" do
        solved = solve_work(issued)

        assert verify(solved[:work], solved[:work_counter])
      end

      test "a counter that does not give enough leading zero bits is refused" do
        challenge = issued
        wrong = (0..).find { |held| !ProofOfWork.solves?(challenge["nonce"], held, BITS) }

        refute verify(challenge["token"], wrong.to_s)
      end

      test "a counter that is not a plain number is refused" do
        solved = solve_work(issued)

        refute verify(solved[:work], " #{solved[:work_counter]}")
        refute verify(solved[:work], nil)
      end

      test "a challenge older than ten minutes is refused" do
        solved = solve_work(issued)

        travel(ProofOfWork::LIFETIME + 1.second) do
          refute verify(solved[:work], solved[:work_counter])
        end
      end

      test "a solved challenge is accepted once" do
        solved = solve_work(issued)

        assert verify(solved[:work], solved[:work_counter])
        refute verify(solved[:work], solved[:work_counter])
      end

      test "a challenge issued to one login is refused for another" do
        solved = solve_work(issued)

        refute verify(solved[:work], solved[:work_counter], bound_to: "login-b")
        assert verify(solved[:work], solved[:work_counter])
      end

      test "a challenge easier than the policy now asks for is refused" do
        solved = solve_work(issued(bits: 2))

        refute verify(solved[:work], solved[:work_counter])
      end

      test "a challenge that was not signed here is refused" do
        solved = solve_work(issued)
        forged = solved[:work].sub(/.\z/) { |last| last == "a" ? "b" : "a" }

        refute verify(forged, solved[:work_counter])
        refute verify("not-a-token", "0")
        refute verify(nil, "0")
      end
    end
  end
end
