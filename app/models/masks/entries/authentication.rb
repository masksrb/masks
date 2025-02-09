module Masks
  module Entries
    class Authentication < OauthEntry
      def session_key
        raw_params[:id]
      end

      def client_id
        raw_params[:id]&.split(":").first
      end

      def session_lifetime
        client.expires_at(:login_attempt)
      end

      def client
        @client ||= (Masks.client(client_id) if client_id)
      end

      def path
        @path ||= session.entry["path"]
      end

      def params
        session.entry["params"]&.with_indifferent_access
      end

      def event
        raw_params[:event]
      end

      def updates
        raw_params[:updates] || {}
      end

      def enter
        oauth_entry { prompt! }
      end
    end
  end
end
