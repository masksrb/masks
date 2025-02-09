module Masks
  module Prompts
    class SecondFactor
      include Masks::Prompt

      match :on_2fa?

      setup do
        prompt = self

        session.structure do
          check Entry::FACTOR2,
                parent: :actor,
                expiry: Masks::NEVER_EXPIRE,
                checked: -> do
                  if prompt.client.second_factor?
                    prompt.actor.second_factor? && checked?
                  else
                    true
                  end
                end
        end
      end

      prompt "profile" do
        if client.second_factor? &&
             (!actor.second_factor? || actor.review_second_factor?)
          extras(second_factor_required: true)
        end
      end

      prompt "second-factor" do
        !session[Entry::FACTOR2]
      end

      event "second-factor:enable", if: -> { !actor.second_factor? } do
        actor.enable_second_factor!

        extras(second_factor_enabled: true)
      end

      def reset!(logout = false)
        session[:actor].expire(Entry::FACTOR2) if logout
      end
    end
  end
end
