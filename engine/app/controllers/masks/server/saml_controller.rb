module Masks
  module Server
    class SamlController < ApplicationController
      skip_forgery_protection only: :sso

      rate_limit to: 60, within: 1.minute, only: %i[sso initiate],
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { refuse("too many sign-in requests from this address", status: :too_many_requests) }

      rescue_from SamlIdentity::Refused do |refusal|
        refuse(refusal.message)
      end

      def metadata
        expires_in 5.minutes, public: true
        render xml: SamlIdentity::Metadata.new(issuer).to_xml
      end

      def sso
        asked = SamlIdentity::Request.read!(request, issuer: issuer)

        saml = { "request_id" => asked.id, "relay_state" => asked.relay_state, "name_id_format" => asked.name_id_format }
        prompt = [ ("login" if asked.force_authn), ("none" if asked.passive) ]

        answer(track_request!(authorization_for(asked.client, asked.acs_url, saml, prompt: prompt)))
      end

      def initiate
        client = Client.authenticating(params[:client_id], protocol: SamlIdentity::PROTOCOL)

        raise SamlIdentity::Refused, "no application is registered here with that id" if client.nil?
        raise SamlIdentity::Refused, "#{client.name} is only signed into from its own sign-in page" unless client.saml_idp_initiated?

        saml = {
          "relay_state" => params[:RelayState].presence,
          "name_id_format" => client.saml_name_id_format.presence || SamlIdentity::PERSISTENT,
          "nonce" => SecureRandom.uuid
        }

        answer(track_request!(authorization_for(client, client.redirect_uris.first, saml)))
      end

      def resume
        pending = pending_request(params[:rid])

        raise SamlIdentity::Refused, "that sign-in has expired or was already answered" unless pending&.saml?

        answer(pending)
      end

      def refused
        pending = refused_request(params[:rid])

        raise SamlIdentity::Refused, "that sign-in has expired" unless pending&.saml?

        post(pending, failure(pending, SamlIdentity::RESPONDER, SamlIdentity::REQUEST_DENIED, "the person signing in was refused"))
      end

      private

        def authorization_for(client, acs_url, saml, prompt: [])
          Authorization.new(
            client_id: client.client_id,
            redirect_uri: acs_url,
            response_type: SamlIdentity::PROTOCOL,
            scope: Scopes.join(SamlIdentity::SCOPES),
            prompt: Scopes.join(prompt.compact),
            saml: saml.compact
          )
        end

        def answer(pending)
          return refuse("that sign-in has already been answered") if pending.consumed?

          login = advance(pending)

          return post(pending, denied(pending, login.refusal.description)) if login.refused?
          return post(pending, denied(pending, "the person has to be asked", second: SamlIdentity::NO_PASSIVE)) if login.prompted? && pending.silent?
          return redirect_to(login.redirect_to, allow_other_host: true) if login.redirect_to.present?
          return prompt(login) unless login.settled?

          complete(pending, login)
        end

        def complete(pending, login)
          claimed = PendingRequest.claim(rid_for(pending))

          return refuse("that sign-in has already been answered") if claimed.nil?

          settle!(login)

          saml = pending.held("saml")
          scopes = pending.scopes_for(current_actor)

          encoded = response_for(pending).success(
            actor: current_actor, session: current_session, name_id_format: saml["name_id_format"], scopes: scopes,
            authenticated_at: login.authenticated_at || current_session&.authenticated_at,
            amr: login.amr.presence || current_session&.amr
          )

          Event.record!(Event::SAML_ASSERTED, actor: current_actor, client: pending.client, scopes: scopes,
                                              initiated: saml["request_id"] ? "service provider" : "masks")

          post(pending, encoded)
        end

        def denied(pending, description, second: SamlIdentity::REQUEST_DENIED)
          PendingRequest.claim(rid_for(pending))

          failure(pending, SamlIdentity::RESPONDER, second, description)
        end

        def failure(pending, status, second, message)
          response_for(pending).failure(status, second, message)
        end

        def response_for(pending)
          SamlIdentity::Response.new(
            issuer: issuer, client: pending.client, destination: pending.redirect_uri,
            in_response_to: pending.held("saml")["request_id"]
          )
        end

        def refused_request(rid)
          return nil if rid.blank? || !tracked(REQUESTS).value?(rid)

          PendingRequest.spent(rid)&.then { |held| held if held.consumed? }
        end

        def post(pending, encoded)
          @client = pending.client
          @destination = pending.redirect_uri
          @saml_response = encoded
          @relay_state = pending.held("saml")["relay_state"]
          @script_nonce = SecureRandom.base64(16)

          response.headers["Content-Security-Policy"] =
            "default-src 'self'; script-src 'nonce-#{@script_nonce}'; frame-ancestors 'none'"
          response.headers["Cache-Control"] = "no-store"

          render :post
        end

        def refuse(description, status: :bad_request)
          @error_code = "invalid_saml_request"
          @error_description = description

          render "masks/server/authorize/error", status: status
        end
    end
  end
end
