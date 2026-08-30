class AuthorizeController < ApplicationController
  include RackOAuth2Endpoint

  def show
    authorization = Authorization.from_request(request)
    attempt = validate(authorization)

    return refuse(attempt.error) if attempt.refused?
    return redirect_to(attempt.location, allow_other_host: true) if attempt.answered?

    return start_login(authorization) if needs_login?(authorization)
    return start_consent(authorization) if needs_consent?(authorization)

    complete(authorization, attempt)
  end

  private

    # rack-oauth2 validates a params hash, not this request, so the same checks
    # run identically on a live authorize and on one resumed out of the session.
    def validate(authorization)
      AuthorizeRequest.new(authorization.to_params).run do |req, res|
        req.unsupported_response_type! unless req.response_type == :code

        client = Client.authenticating(req.client_id)
        req.invalid_request!("no client is registered with that client_id") if client.nil?
        req.invalid_request!("redirect_uri is required") if req.redirect_uri.blank?

        req.verify_redirect_uri!(client.redirect_uris)
        req.verified_redirect_uri = with_issuer(req.verified_redirect_uri)
        res.redirect_uri = req.verified_redirect_uri

        permit(req) { authorization.validate! }

        if authorization.silent? && (needs_login?(authorization) || needs_consent?(authorization))
          req.interaction_required!
        end
      end
    end

    def permit(req)
      yield
    rescue Policy::Denied => denial
      raise unless denial.redirectable

      req.bad_request!(denial.error.to_sym, denial.description)
    end

    def needs_login?(authorization)
      authorization.reauthenticate? || current_actor.nil?
    end

    def needs_consent?(authorization)
      return false if needs_login?(authorization)
      return true if authorization.consent?

      !Consent.covers?(
        actor: current_actor,
        client: authorization.client,
        scopes: authorization.scopes_for(current_actor),
        audience: authorization.audience
      )
    end

    def start_login(authorization)
      session[:authorization] = authorization.to_session

      redirect_to login_path
    end

    def start_consent(authorization)
      session[:authorization] = authorization.to_session

      redirect_to consent_path
    end

    def complete(authorization, attempt)
      code = authorization.issue_code!(actor: current_actor)
      session.delete(:authorization)

      render_rack(attempt.approve!(code.secret))
    end

    # rack-oauth2 raises rather than answers when it has not yet verified the
    # redirect_uri — refusing to hand an attacker an open redirect. Once the URI
    # is verified it redirects on its own and never reaches here.
    def refuse(error)
      client = Client.authenticating(params[:client_id])
      target = params[:redirect_uri].to_s

      if client && target.present? && client.redirect_uri?(target)
        redirect_to refusal_uri(target, error), allow_other_host: true
      else
        render json: {
          "error" => error.error.to_s,
          "error_description" => error.description
        }, status: error.status
      end
    end

    def refusal_uri(target, error)
      uri = URI.parse(with_issuer(target))
      query = Rack::Utils.parse_query(uri.query)

      query["error"] = error.error.to_s
      query["error_description"] = error.description
      query["state"] = params[:state] if params[:state].present?

      uri.query = Rack::Utils.build_query(query)
      uri.to_s
    end

    def with_issuer(uri)
      parsed = URI.parse(uri.to_s)
      query = Rack::Utils.parse_query(parsed.query)
      query["iss"] = issuer.url
      parsed.query = Rack::Utils.build_query(query)

      parsed.to_s
    end
end
