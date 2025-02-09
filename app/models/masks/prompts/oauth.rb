module Masks
  module Prompts
    class OAuth
      include Masks::Prompt

      match { oauth_request }

      oauth do
        entry.scopes = oauth_request.scopes

        approved! if client.auto_consent?
      end

      auth { oauth_request.validate_scopes!(actor) }

      prompt "authorize" do
        !approved? && !denied?
      end

      postauth { finalize! if trusted? }

      def finalize!
        oauth_request.denied! if denied?
        oauth_request.approve!(actor:, device:) if approved?
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
