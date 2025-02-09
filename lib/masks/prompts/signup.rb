module Masks
  module Prompts
    class Signup
      include Masks::Prompt

      setting :signup, :json

      match { current_client.allow_signup? }

      setup do
        session.structure do
          key :signup, parent: :endpoint, expiry: Masks::NEVER_EXPIRE
        end
      end

      reset { session[:signup] = false }

      prompt "signup" do
        extras(
          signup: {
            actor: {
              nickname: current_actor&.nickname,
              email: current_actor&.login_email&.address,
            },
          },
        )

        (current_actor&.new_record? || session[:signup])
      end

      event "signup:confirm" do
        session[:signup] = false
      end

      event "signup:start" do
        session[:signup] = true

        self.prompt = "signup"
      end

      event "signup:create", if: :signup do
        actor = current_client.signup(**signup.symbolize_keys)

        if actor.save
          sibling(:identifier).identify!(actor.identifier, actor)

          session[Prompt::FACTOR1] = current_client.expires_at(:signup_login)

          extras(signup: { confirmed: true })

          self.prompt = "signup"
        else
          extras(signup: { error: actor.errors.full_messages.first })

          warn! "actor-invalid", prompt: "signup"
        end
      end
    end
  end
end
