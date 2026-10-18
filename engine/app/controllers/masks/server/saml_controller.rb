module Masks
  module Server
    class SamlController < ApplicationController
      include SamlFarewells

      skip_forgery_protection only: %i[sso slo]

      rate_limit to: 60, within: 1.minute, only: %i[sso initiate slo],
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

      def slo
        carried = request.post? ? request.request_parameters : request.query_parameters

        carried.key?("SAMLResponse") ? farewell_answered : logout_requested
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

        def logout_requested
          asked = SamlIdentity::LogoutRequest.read!(request, issuer: issuer)

          found = SamlParticipation.where(client: asked.client, name_id: asked.name_id)
          found = found.where(session_index: asked.session_indexes) if asked.session_indexes.any?
          found = found.includes(:session).to_a

          finish = { "client_id" => asked.client.client_id, "in_response_to" => asked.id, "relay_state" => asked.relay_state,
                     "known" => found.any? }

          found.each(&:claimed?)

          ending = found.map(&:session).uniq.select { |held| held.revoked_at.nil? }
          browser = ending.find { |held| held.id == current_session&.id }
          departing = browser ? SamlParticipation.claim!(browser.saml_participations) : []

          ending.each { |held| held == browser ? sign_out : end_elsewhere(held, asked.client) }

          farewell(departing, finish: finish)
        end

        def farewell_answered
          reply = SamlIdentity::LogoutReply.read!(request, issuer: issuer)
          farewells = SamlIdentity::Farewells.resume(reply.in_response_to, client: reply.client)

          raise SamlIdentity::Refused, "that LogoutResponse answers nothing masks is waiting on" if farewells.nil?

          proceed(farewells)
        end

        def end_elsewhere(session, client)
          session.revoke!

          Event.record!(Event::SESSION_ENDED, actor: session.actor, by: nil, device: session.device, client: client)
        end

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

          assertion = response_for(pending)
          encoded = assertion.success(
            actor: current_actor, session: current_session, name_id_format: saml["name_id_format"], scopes: scopes,
            authenticated_at: current_session&.authenticated_at,
            amr: login.amr.presence || current_session&.amr
          )

          Event.record!(Event::SAML_ASSERTED, actor: current_actor, client: pending.client, scopes: scopes,
                                              initiated: saml["request_id"] ? "service provider" : "masks")

          participated!(pending.client, assertion, saml["name_id_format"])

          post(pending, encoded)
        end

        def participated!(client, assertion, name_id_format)
          return if current_session.nil?

          SamlParticipation.record!(session: current_session, client: client, name_id: assertion.name_id, name_id_format: name_id_format)
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

        def post(pending, encoded)
          post_saml(pending.client, pending.redirect_uri, "SAMLResponse", encoded, relay_state: pending.held("saml")["relay_state"])
        end

        def refuse(description, status: :bad_request)
          @error_code = "invalid_saml_request"
          @error_description = description

          render "masks/server/authorize/error", status: status
        end
    end
  end
end
