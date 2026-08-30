class AuthorizeController < ApplicationController
  def show
    authorization = Authorization.from_request(request)

    ClientPolicy.new(authorization).call
    authorization.validate!

    if authorization.reauthenticate? || current_actor.nil?
      return start_login(authorization)
    end

    unless consented?(authorization)
      return start_consent(authorization)
    end

    complete(authorization)
  rescue Policy::Denied => denial
    refuse(authorization, denial)
  end

  private

    def consented?(authorization)
      return false if authorization.consent?

      Consent.covers?(
        actor: current_actor,
        client: authorization.client,
        scopes: authorization.granted_scopes,
        audience: authorization.audience
      )
    end

    def start_login(authorization)
      return refuse(authorization, silently_denied) if authorization.silent?

      session[:authorization] = authorization.to_session
      redirect_to login_path
    end

    def start_consent(authorization)
      return refuse(authorization, silently_denied) if authorization.silent?

      session[:authorization] = authorization.to_session
      redirect_to consent_path
    end

    def complete(authorization)
      code = authorization.issue_code!(actor: current_actor)
      session.delete(:authorization)

      redirect_to authorization.redirect_with(issuer: issuer, code: code.secret),
                  allow_other_host: true
    end

    def silently_denied
      Policy::Denied.new(
        "interaction_required",
        "the request set prompt=none but sign-in or consent is needed",
        redirectable: true
      )
    end

    def refuse(authorization, denial)
      if denial.redirectable && authorization&.client && authorization.client.redirect_uri?(authorization.redirect_uri)
        redirect_to authorization.redirect_with(
          issuer: issuer,
          error: denial.error,
          error_description: denial.description
        ), allow_other_host: true
      else
        render json: denial.to_h, status: denial.status
      end
    end
end
