module Masks
  class LoginEndpoint
    include Masks::Endpoint

    setting :allow_updates,
            :boolean,
            default: -> { session.rails_request.post? }
    setting :allow_internal,
            :boolean,
            default: -> { !session.rails_request.GET.key?(:client_id) }
    setting :client_id,
            :string,
            oauth: true,
            default: -> { Masks.conf.internal_client }
    setting :response_type, :string, oauth: true
    setting :grant_type, :string, oauth: true
    setting :redirect_uri, :string, oauth: true
    setting :code_challenge, :string, oauth: true
    setting :code_challenge_method, :string, oauth: true
    setting :login_hint, :string, oauth: true
    setting :prompt_hint, :string, oauth: true, key: :prompt
    setting :scope, :string, oauth: true
    setting :state, :string, oauth: true
    setting :nonce, :string, oauth: true
    setting :event,
            :string,
            public: true,
            default: -> { settings[:event] if allow_updates? }
    setting :scopes, [:string]

    attr_writer :prompt
    attr_accessor :login_link

    def settings
      session.rails_request.params
    end

    def session_key
      Digest::SHA256.hexdigest(oauth_params.to_query)
    end

    def oauth_params
      @oauth_params ||=
        if client
          client
            .oauth_params(settings.slice(*oauth_keys).to_h.stringify_keys)
            .sort_by { |k, _| k.to_s }
            .to_h
            .with_indifferent_access
        else
          {}
        end
    end

    def public_keys
      self
        .class
        .settings_json
        .map { |k, conf| k if conf[:public] || conf[:oauth] }
        .compact
    end

    def oauth_keys
      self.class.settings_json.map { |k, conf| k if conf[:oauth] }.compact
    end

    def session_lifetime
      client&.expires_at(:login)
    end

    def client
      @client ||= Masks.client(client_id, internal: allow_internal?)
    end

    def public_json
      super.merge(
        prompt:,
        trusted: trusted?,
        settled: settled?,
        scopes: Masks.scopes.map(scopes),
        login_link: login_link ? { expires_at: login_link.expires_at } : nil,
        actor: actor&.public_json,
        providers: client&.providers&.map(&:public_json),
      )
    end

    def event?(name)
      event && event.to_s == name.to_s
    end

    def actor
      if settled?
        @actor ||= Masks::Actor.find(settlement["actor"]) if settlement["actor"]
      else
        session.current_actor
      end
    end

    def dispatch(*args, **opts)
      prompts.values.each { |p| p.dispatch(*args, **opts) }
    end

    def prompt
      @prompt || error || settlement["prompt"]
    end

    def prompts
      @prompts ||=
        Masks
          .conf
          .prompts
          .map do |cls|
            updates =
              if allow_updates?
                if cls.settings
                  settings.slice(*cls.settings.symbolize_keys.keys)
                end
              end

            [cls.to_s, cls.new(self, updates)]
          end
          .to_h
    end

    def session_lifetime
      client&.expires_at(:login_attempt)
    end

    def trusted?
      @env && client && session[Prompt::FACTOR1] && session[Prompt::FACTOR2]
    end

    def redirect_uri
      settlement["redirect_uri"] if settled?
    end

    def warn!(*args, prompt: nil)
      super(*args)

      self.prompt = prompt if prompt
    end

    def settled!(prompt: "success", error: nil, redirect_uri: nil)
      if error
        self.prompt = error
        self.error = error
      else
        self.prompt = prompt
      end

      if session.structure.bag?(:endpoint)
        session.endpoint["settlement"] = {
          "settled" => true,
          "prompt" => self.prompt,
          "redirect_uri" => redirect_uri,
          "actor" => session.current_actor&.id,
        }

        dispatch("login") if !error && session.current_actor

        session.endpoint.refresh(request_id)
      end

      @settled = true
    end

    def settlement
      if @env
        session.endpoint["settlement"] ||= {}
      else
        {}
      end
    end

    def settled?
      !!(@settled || session.endpoint&.data&.dig("settlement", "settled"))
    end

    def before_request
      client ? dispatch(Prompt::SETUP) : settled!(error: "missing-client")
    end

    def request
      dispatch(Prompt::SETUP)

      oauth =
        Masks::Shims::OauthRequest.call(client, oauth_params) do |req|
          session.structure do
            current :actor, parent: :device, expiry: Masks::NEVER_EXPIRE
            current :oauth_request
          end

          session[:oauth_request] = req

          dispatch(Prompt::OAUTH)
          dispatch(Prompt::PREAUTH)
          dispatch(event:) if event && allow_updates?
          dispatch(Prompt::AUTH)
          dispatch(Prompt::POSTAUTH)
        end

      if oauth.error || oauth.approved?
        redirect_uri =
          if oauth.approved? && client.internal?
            oauth.original_redirect_uri
          else
            oauth.redirect_uri
          end

        settled!(error: oauth.error, redirect_uri:)
      end

      dispatch(Prompt::CLEANUP)
    end

    def call!
      if client
        request unless settled?
      else
        settled!(error: "missing-client") unless prompt
      end

      @env["masks.login"] = public_json

      nil
    end
  end
end
