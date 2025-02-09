module Masks
  module Prompts
    class Internal
      include Masks::Prompt

      match { current_oauth_request }

      setup { Masks::InternalEndpoint.structure(session) }

      login { Masks::InternalEndpoint.login(session) }
    end
  end
end
