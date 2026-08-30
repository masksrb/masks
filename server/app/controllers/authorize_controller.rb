class AuthorizeController < ApplicationController
  include RackOAuth2Endpoint

  def show
    outcome = catch(:interaction) { { rack: endpoint.call(request.env) } }

    return redirect_to(outcome) unless outcome.is_a?(Hash)

    render_rack(outcome[:rack])
  end

  private

    def endpoint
      Rack::OAuth2::Server::Authorize.new do |req, res|
        req.unsupported_response_type! unless req.response_type == :code

        client = Client.authenticating(req.client_id)
        req.invalid_request!("no client is registered with that client_id") if client.nil?

        req.verify_redirect_uri!(client.redirect_uris)
        req.verified_redirect_uri = with_issuer(req.verified_redirect_uri)
        res.redirect_uri = req.verified_redirect_uri

        authorization = Authorization.from_request(request)

        permit(req) { authorization.validate! }

        if authorization.reauthenticate? || current_actor.nil?
          interact(req, authorization, login_path)
        end

        unless consented?(authorization)
          interact(req, authorization, consent_path)
        end

        code = permit(req) { authorization.issue_code!(actor: current_actor) }
        session.delete(:authorization)

        res.code = code.secret
        res.approve!
      end
    end

    def permit(req)
      yield
    rescue Policy::Denied => denial
      raise unless denial.redirectable

      req.bad_request!(denial.error.to_sym, denial.description)
    end

    def interact(req, authorization, path)
      if authorization.silent?
        req.bad_request!(
          :interaction_required,
          "the request set prompt=none but sign-in or consent is needed"
        )
      end

      session[:authorization] = authorization.to_session

      throw :interaction, path
    end

    def consented?(authorization)
      return false if authorization.consent?

      Consent.covers?(
        actor: current_actor,
        client: authorization.client,
        scopes: authorization.scopes_for(current_actor),
        audience: authorization.audience
      )
    end

    def with_issuer(uri)
      parsed = URI.parse(uri.to_s)
      query = Rack::Utils.parse_query(parsed.query)
      query["iss"] = issuer.url
      parsed.query = Rack::Utils.build_query(query)

      parsed.to_s
    end
end
