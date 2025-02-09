module Masks
  module Entries
    class OAuthEntry < Masks::Entry
      def session_lifetime
        client.expires_at(:authorization)
      end

      def oauth_entry(&block)
        oauth =
          Masks::Shims::OAuthRequest.call(client, params) do |oauth|
            session.structure { current :oauth_request }
            session[:oauth_request] = oauth

            dispatch(Prompt::OAUTH)

            block.call
          end

        return unless oauth.error || oauth.approved?

        redirect_uri =
          if oauth.approved? && client.internal?
            oauth.original_redirect_uri
          else
            oauth.redirect_uri
          end

        settled!(error: oauth.error, redirect_uri:)
      end
    end
  end
end
