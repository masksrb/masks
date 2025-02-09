module Masks
  module Prompts
    class Internal
      include Masks::Prompt

      match { oauth_request }

      setup do
        session.structure do
          current :internal_token,
                  parent: :device,
                  expiry: Masks::NEVER_EXPIRE,
                  null: true
        end
      end

      login do
        if token = oauth_request.internal_token
          bag = session.internal_token.with(client)
          bag["token"] = token.secret
          bag.refresh(token.expires_at)
        end
      end
    end
  end
end
