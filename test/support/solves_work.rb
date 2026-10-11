module Masks
  module Server
    module SolvesWork
      def solve_work(work)
        counter = (0..).find { |held| ProofOfWork.solves?(work["nonce"], held, work["bits"]) }

        { work: work["token"], work_counter: counter.to_s }
      end
    end
  end
end
