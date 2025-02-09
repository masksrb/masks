module Masks
  module Prompts
    class SingleSignOn
      include Masks::Prompt

      setting :sso_id, :string
      setting :sso_origin, :string
      setting :delete_sso_id, :string

      match { current_client.allow_sso? }

      setup { structure_session(current_client) }

      def structure_session(client = nil)
        session.structure do
          key :single_sign_on, parent: :endpoint, expiry: Masks::NEVER_EXPIRE

          current :sso_request,
                  parent: :device,
                  expiry: client ? -> { client.expires_at(:sso_request) } : nil,
                  track: true,
                  null: true
        end
      end

      preauth do
        if @callback_client
          callback_phase
        else
          sign_on! if single_sign_on&.persisted?
        end
      end

      postauth(always: true) do
        add_extras if session[:single_sign_on] && !extras["sso"]
      end

      event "reset" do
        reset_callback
      end

      def callback_client
        @callback_client ||=
          begin
            structure_session

            @provider = login.provider

            session[:sso_request] = @provider

            return unless session.sso_request.data

            add_extras(origin: session.sso_request.data["origin"])

            return if session.sso_request["attempted"]

            client =
              Masks.clients.discover(
                session.sso_request.data&.fetch("client", nil),
              )
            client if client&.provider?(@provider)
          end
      end

      def callback_phase
        return unless current_client

        session.sso_request["attempted"] = true

        @omniauth =
          Masks::Shims::Omniauth.callback(
            @provider,
            request.GET,
            session: session.sso_request.data["session"] || {},
          )

        session[:single_sign_on] = {
          "omniauth" => @omniauth.auth&.as_json,
          "provider" => provider.key,
        }

        # Actors that have already linked to a provider are not prompted
        # to re-link accounts. It is assumed this is what they want. Since
        # tokens may be refreshed, the SSO record must be updated automatically.
        if trusted? && !single_sign_on.persisted?
          link_sso!
        elsif single_sign_on.persisted?
          sign_on!
        end
      rescue => e
        reset_callback
      end

      event "sso:request" do
        next unless sso_id

        @provider = Masks.provider(sso_id, client: current_client)

        next unless @provider

        request_phase
        add_extras

        self.prompt = "sso"
      end

      def request_phase
        origin =
          begin
            URI(sso_origin)
          rescue StandardError
            nil
          end

        return warn! "invalid-origin" unless origin

        @omniauth = Masks::Shims::Omniauth.request(provider)

        extras(redirect: @omniauth.redirect_uri)

        session[:sso_request] = @provider
        session.sso_request.update(
          {
            "id" => login.session_key,
            "url" => login.url,
            "client" => current_client.key,
            "origin" => origin.to_s,
            "session" => @omniauth.session,
            "state" => @omniauth.state,
          },
        )
      end

      private :request_phase

      event "sso:login" do
        session[:single_sign_on]["accepted"] = true if session[:single_sign_on]
      end

      event "sso:reset" do
        reset_request
        reset_callback
      end

      event "sso:link" do
        if link_sso!
          add_extras
          reset_callback
          reset_request
        else
          add_extras
        end

        self.prompt = "sso-link"
      end

      event "sso:delete", trusted: true, factors: FIRST_OR_SECOND do
        if delete_sso_id
          current_actor
            .single_sign_ons
            .find_by(key: delete_sso_id)
            &.permanently_delete
        end
      end

      prompt "sso-accept" do
        session[:single_sign_on] && !session[:single_sign_on]["accepted"] &&
          !trusted?
      end

      prompt "sso-link", if: -> { session[:single_sign_on] }, trusted: true do
        single_sign_on.new_record?
      end

      private

      def sign_on!
        return unless single_sign_on&.persisted?

        actor = single_sign_on.actor

        sibling(:identifier).identify!(actor.identifier, actor)

        session[Prompt::FACTOR1] = current_client.expires_at(:sso_login)

        reset_request
        reset_callback
      end

      def link_sso!
        return unless single_sign_on&.new_record?

        single_sign_on.actor = current_actor

        if single_sign_on.save
          true
        else
          warn! "invalid-sso", prompt: "sso-link"

          false
        end
      end

      def reset_request
        session.sso_request.with(provider).expire
      end

      def reset_callback
        session.single_sign_on.expire
      end

      def sso_provider
        @sso_provider ||=
          (
            if session[:single_sign_on]
              Masks.provider(
                session[:single_sign_on]["provider"],
                client: current_client,
              )
            end
          )
      end

      def provider
        @provider ||= sso_provider
      end

      def provider_json(p = nil)
        p = p || provider
        return unless p
        p.slice(:name).merge(id: p.key, type: p.public_type)
      end

      def sso_json
        return unless single_sign_on

        {
          provider: provider_json(sso_provider),
          identifier: single_sign_on&.identifier,
          avatar: single_sign_on&.avatar,
          linked: single_sign_on&.persisted?,
        }
      end

      def add_extras(**extras)
        extras(provider: provider_json, sso: sso_json, **extras)
      end

      def single_sign_on
        unless provider && session.structure.bag?(:single_sign_on) &&
                 session[:single_sign_on]
          return
        end

        @single_sign_on ||=
          provider
            .single_sign_ons
            .find_or_initialize_by(
              key: session[:single_sign_on].dig("omniauth", "uid"),
            )
            .tap { |r| r.settings = session[:single_sign_on]["omniauth"] }
      end
    end
  end
end
