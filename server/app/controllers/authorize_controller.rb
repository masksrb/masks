class AuthorizeController < ApplicationController
  include RackOAuth2Endpoint

  skip_forgery_protection only: :show, if: -> { request.post? }

  def show
    authorization = Authorization.from_request(request)
    attempt = validate(authorization)

    return refuse(attempt.error) if attempt.refused?
    return redirect_to(attempt.location, allow_other_host: true) if attempt.answered?

    pending = track_request!(authorization)
    return spent(pending) if pending.consumed?

    login = advance(pending)

    return answer(deny(pending, login.refusal.error, login.refusal.description)) if login.refused?
    return interaction_required(pending) if login.prompted? && pending.silent?
    return prompt(login) unless login.settled?

    complete(pending, attempt, login)
  end

  private

    def validate(authorization)
      AuthorizeRequest.new(authorization.to_params).run do |req, res|
        req.unsupported_response_type! unless req.response_type == :code

        client = Client.authenticating(req.client_id)
        req.bad_request!(:invalid_client, "no client is registered with that client_id") if client.nil?
        req.invalid_request!("redirect_uri is required") if req.redirect_uri.blank?

        req.verify_redirect_uri!(client.redirect_uris)
        req.verified_redirect_uri = with_issuer(req.verified_redirect_uri)
        res.redirect_uri = req.verified_redirect_uri

        req.bad_request!(:request_not_supported, "request objects are not supported") if authorization.request_object?
        req.bad_request!(:request_uri_not_supported, "request_uri is not supported") if authorization.request_uri?

        permit(req) { authorization.validate! }
      end
    end

    def permit(req)
      yield
    rescue Policy::Denied => denial
      raise unless denial.redirectable

      req.bad_request!(denial.error.to_sym, denial.description)
    end

    def advance(pending)
      Login.new(
        store: session[LoginsController::STORE] ||= {},
        request: pending,
        session: current_session,
        rid: rid_for(pending)
      ).update
    end

    def prompt(login)
      @login = login

      render template: "logins/show"
    end

    def complete(pending, attempt, login)
      claimed = PendingRequest.claim(rid_for(pending))
      return spent(pending) if claimed.nil?

      sign_in(login.actor) if current_session.nil?
      session.delete(LoginsController::STORE)

      code = claimed.issue_code!(
        actor: current_actor,
        authenticated_at: login.authenticated_at || current_session&.authenticated_at
      )

      render_rack(attempt.approve!(code.secret))
    end

    def spent(pending)
      answer(deny(pending, "invalid_request", "that sign-in request has already been answered"))
    end

    def interaction_required(pending)
      answer(deny(pending, "interaction_required", "this request cannot be answered without asking the person"))
    end

    def answer(location)
      redirect_to location, allow_other_host: true
    end

    def refuse(error)
      client = Client.authenticating(params[:client_id])
      target = params[:redirect_uri].to_s

      if client && target.present? && client.redirect_uri?(target)
        return redirect_to refusal_uri(target, error), allow_other_host: true
      end

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
