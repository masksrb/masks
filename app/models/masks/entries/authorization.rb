module Masks
  module Entries
    class Authorization < OauthEntry
      PARAMS = %w[
        client_id
        response_type
        grant_type
        redirect_uri
        code_challenge
        code_challenge_method
        login_hint
        prompt
        scope
        state
        nonce
      ]

      def session_key
        "#{client.key}:#{Digest::SHA256.hexdigest(params.to_query)}" if client
      end

      def session_lifetime
        client&.expires_at(:login_attempt)
      end

      def rails_params
        session.rails_request.params
      end

      def client
        raw_params[:client]
      end

      def params
        @params ||=
          client
            .oauth_params(rails_params.slice(*PARAMS).to_h.stringify_keys)
            .sort_by { |k, _| k.to_s }
            .to_h
      end

      def enter
        oauth_entry do
          session.entry["path"] = session.rails_request.path
          session.entry["params"] = params

          prompt!
        end
      end
    end
  end
end
