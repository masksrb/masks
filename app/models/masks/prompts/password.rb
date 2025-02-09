module Masks
  module Prompts
    class Password
      include Masks::Prompt

      match { client.allow_passwords? }

      event "password:verify", if: :actor do
        self.prompt = "first-factor" unless verify_password
      end

      event "password:change", trusted: true, factors: FIRST_OR_SECOND do
        actor.overwrite_password(updates["value"])

        warn! "invalid-password" unless actor.save
      end
    end
  end
end
