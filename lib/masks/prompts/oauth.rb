module Masks
  module Prompts
    class Oauth
      include Masks::Prompt

      match { current_oauth_request }

      oauth do
        login.scopes = current_oauth_request.scopes

        approved! if current_client.auto_consent?
      end

      auth { current_oauth_request.validate_scopes!(current_actor) }

      prompt "authorize" do
        !approved? && !denied?
      end

      postauth { finalize! if trusted? }

      def finalize!
        current_oauth_request.denied! if denied?

        if approved?
          current_oauth_request.approve!(
            actor: current_actor,
            device: current_device,
          )
        end
      end

      event "authorize" do
        approved!
      end

      event "deny" do
        session.client["approved"] = false
        session.client["denied"] = true
      end

      private

      def approved!
        session.client["approved"] = true
      end

      def approved?
        session.client["approved"]
      end

      def denied?
        session.client["denied"]
      end
    end
  end
end
