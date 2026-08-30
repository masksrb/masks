class AuthorizeController < ApplicationController
  include RackOAuth2Endpoint

  # A POST authorization request is a cross-site form post from the client, and
  # it carries no session of ours to forge against.
  skip_forgery_protection only: :show, if: -> { request.post? }

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
        req.bad_request!(:invalid_client, "no client is registered with that client_id") if client.nil?
        req.invalid_request!("redirect_uri is required") if req.redirect_uri.blank?

        req.verify_redirect_uri!(client.redirect_uris)
        req.verified_redirect_uri = with_issuer(req.verified_redirect_uri)
        res.redirect_uri = req.verified_redirect_uri

        # A request object carries signed copies of state and nonce. Reading the
        # query and ignoring the object would let unsigned parameters beat
        # signed ones, so refuse the way OIDC Core 6 says an issuer that does
        # not support them must. After the redirect_uri is verified, so the
        # refusal reaches the client rather than the browser.
        req.bad_request!(:request_not_supported, "request objects are not supported") if authorization.request_object?
        req.bad_request!(:request_uri_not_supported, "request_uri is not supported") if authorization.request_uri?

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
      return true if authorization.reauthenticate? || current_actor.nil?

      stale?(authorization.max_age)
    end

    # max_age is a ceiling on how long ago the session authenticated, not on
    # how long ago a token was issued, which is why auth_time has to be the
    # session's and travel with the code.
    def stale?(max_age)
      return false if max_age.nil?

      authenticated_at = current_session&.authenticated_at

      authenticated_at.nil? || authenticated_at < max_age.seconds.ago
    end

    def needs_consent?(authorization)
      return false if needs_login?(authorization)
      return true if authorization.consent?
      return false if authorization.client&.approved?

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
      code = authorization.issue_code!(
        actor: current_actor,
        authenticated_at: current_session&.authenticated_at
      )
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
        return redirect_to refusal_uri(target, error), allow_other_host: true
      end

      # There is nowhere safe to send this, so the person in the browser is the
      # one who has to read it. A JSON body is not a refusal a human can act on,
      # and it is what a browser was being handed here.
      @error_code = error.error.to_s
      @error_description = error.description

      respond_to do |format|
        format.html { render :error, status: error.status }
        format.any do
          render json: {
            "error" => @error_code,
            "error_description" => @error_description
          }, status: error.status
        end
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
