module Masks
  module Prompts
    class FirstFactor
      include Masks::Prompt

      match { true }

      setup do
        session.structure do
          check Prompt::FACTOR1, expiry: Masks::NEVER_EXPIRE, parent: :actor
        end
      end

      prompt "first-factor" do
        !session[Prompt::FACTOR1]
      end

      logout { session[Prompt::FACTOR1].expire }
    end
  end
end
