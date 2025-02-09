module Masks
  module Prompts
    class FirstFactor
      include Masks::Prompt

      match { true }

      setup do
        session.structure do
          check Entry::FACTOR1, expiry: Masks::NEVER_EXPIRE, parent: :actor
        end
      end

      prompt "first-factor" do
        !session[Entry::FACTOR1]
      end

      logout { session[Entry::FACTOR1].expire }
    end
  end
end
