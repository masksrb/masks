module Masks
  class ProviderEndpoint < LoginEndpoint
    setting :provider_id,
            :string,
            default: -> { session.rails_request.params[:provider_id] }

    def allow_updates
      false
    end

    def session_lifetime
      Masks::NEVER_EXPIRE
    end

    def url
      sso_request.data&.fetch("url", nil)
    end

    def client
      @client ||= load_client
    end

    def session_key
      @session_key ||= sso_request.data&.fetch("id", nil)
    end

    def origin
      sso_request.data&.fetch("origin", nil)
    end

    def sso_request
      @sso_request ||= session.sso_request.with(provider)
    end

    def provider
      @provider ||= Masks.provider(provider_id)
    end

    # def before_request
    #   if client && provider
    #     prompts["Masks::Prompts::SingleSignOn"]&.callback_phase = true
    #   else
    #     self.prompt = "sso-error"
    #   end
    # end

    def public_json
      super.merge(provider: provider&.public_json)
    end

    private

    def load_client
      if client = sso_prompt.callback_client
        client
      else
        self.prompt = "sso-error"
      end
    end

    def sso_prompt
      prompts["Masks::Prompts::SingleSignOn"]
    end
  end
end
