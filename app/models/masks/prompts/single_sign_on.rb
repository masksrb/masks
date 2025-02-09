module Masks
  module Prompts
    class SingleSignOn
      include Masks::Prompt

      match { client.allow_sso? }

      attr_accessor :callback

      setup do
        prompt = self

        session.structure do
          key :single_sign_on, parent: :entry, expiry: Masks::NEVER_EXPIRE

          current :sso_request,
                  parent: :device,
                  expiry: -> { prompt.client.expires_at(:sso_request) },
                  track: true,
                  null: true
        end
      end

      def callback!
        @provider = entry.provider

        session[:sso_request] = @provider

        return unless session.sso_request.data

        add_extras(origin: session.sso_request.data["origin"])

        return if session.sso_request["attempted"]

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
      end

      preauth { sign_on! if single_sign_on&.persisted? }

      postauth(always: true) do
        add_extras if session[:single_sign_on] && !extras["sso"]
      end

      reset { reset_callback }

      event "sso:request" do
        next unless updates["provider"]

        @provider = Masks.provider(updates["provider"], client:)

        next unless @provider

        request_phase
        add_extras

        self.prompt = "sso"
      end

      def request_phase
        origin =
          begin
            URI(updates["origin"])
          rescue StandardError
            nil
          end

        return warn! "invalid-origin" unless origin

        @omniauth = Masks::Shims::Omniauth.request(provider)

        extras(redirect: @omniauth.redirect_uri)

        session[:sso_request] = @provider
        session.sso_request.update(
          {
            "entry" => entry.id,
            "client" => client.key,
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

      event "sso:unlink", trusted: true, factors: FIRST_OR_SECOND do
        if updates["sso"]
          actor.single_sign_ons.find_by(key: updates["sso"])&.permanently_delete
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

        session[Entry::FACTOR1] = client.expires_at(:first_factor_sso)

        reset_request
        reset_callback
      end

      def link_sso!
        return unless single_sign_on&.new_record?

        single_sign_on.actor = actor

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
              Masks.provider(session[:single_sign_on]["provider"], client:)
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
        return unless provider && session[:single_sign_on]

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
