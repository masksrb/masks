module Masks
  module Prompts
    class SecondFactor
      include Masks::Prompt

      match :on_2fa?

      setup do
        prompt = self

        session.structure do
          check Prompt::FACTOR2,
                parent: :actor,
                expiry: Masks::NEVER_EXPIRE,
                checked: -> do
                  if prompt.current_client.second_factor?
                    prompt.current_actor&.second_factor? && checked?
                  else
                    true
                  end
                end
        end
      end

      prompt "profile" do
        if current_client.second_factor? &&
             (
               !current_actor.second_factor? ||
                 current_actor.review_second_factor?
             )
          extras(second_factor_required: true)
        end
      end

      prompt "second-factor" do
        !session[Prompt::FACTOR2]
      end

      event "second-factor:enable", if: -> { !current_actor.second_factor? } do
        current_actor.enable_second_factor!

        extras(second_factor_enabled: true)
      end

      def reset!(logout = false)
        session[:actor].expire(Prompt::FACTOR2) if logout
      end
    end
  end
end
