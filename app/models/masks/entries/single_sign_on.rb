module Masks
  module Entries
    class SingleSignOn < OAuthEntry
      def client
        @client ||= load_entry
      end

      def origin
        sso_request.data&.fetch("origin", nil)
      end

      def session_key
        @session_key ||= sso_request.data&.fetch("entry", nil)
      end

      def sso_request
        @sso_request ||= session.sso_request.with(provider)
      end

      def params
        return {} unless session_key

        session.entry.with(session_key)["params"]
      end

      def provider
        @provider ||= Masks.provider(raw_params[:provider_id])
      end

      def callback
        session.rails_request.GET
      end

      def enter
        dispatch(Prompt::SETUP)

        prompts["Masks::Prompts::SingleSignOn"].callback!
      end

      private

      def load_entry
        session.structure do
          current :sso_request, parent: :device, track: true, null: true
        end

        provider.load_client(sso_request.data&.fetch("client", nil))
      end
    end
  end
end
