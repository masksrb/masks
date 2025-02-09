module Masks
  module Prompts
    class Internal
      include Masks::Prompt

      match { current_oauth_request }

      setup { Masks::ProtectedEndpoint.structure(session) }
      login do
        Masks::ProtectedEndpoint.login(
          session,
          current_oauth_request.internal_token,
        )
      end
    end
  end
end
