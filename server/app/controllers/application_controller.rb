class ApplicationController < ActionController::Base
  class TenantMissing < StandardError; end

  around_action :within_tenant

  helper_method :current_actor, :current_tenant

  rescue_from TenantMissing, with: :no_such_tenant
  rescue_from Policy::Denied, with: :policy_denied

  private

    def current_tenant
      @current_tenant ||= Tenant.resolve(request.host) || raise(TenantMissing)
    end

    def within_tenant
      Current.origin = origin

      Tenant.switch(current_tenant) { yield }
    end

    def origin
      template = ENV["MASKS_PUBLIC_ORIGIN_TEMPLATE"].presence
      return request.base_url if template.nil?

      format(template, subdomain: request.host.split(".").first)
    end

    def issuer
      @issuer ||= Issuer.new(current_tenant, Current.origin)
    end

    def current_session
      return @current_session if defined?(@current_session)

      @current_session = Session.resume(cookies.encrypted[:masks_session])
    end

    def current_actor
      current_session&.actor
    end

    def sign_in(actor)
      carried = session.to_hash.slice("authorization", "masks_return_to")
      reset_session
      carried.each { |key, value| session[key] = value }

      record = Session.start!(
        actor: actor,
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      )

      cookies.encrypted[:masks_session] = {
        value: record.secret,
        expires: record.expires_at,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }

      actor.update!(last_login_at: Time.current)
      @current_session = record
    end

    def sign_out
      current_session&.revoke!
      cookies.delete(:masks_session)
      @current_session = nil
    end

    def pending_authorization
      Authorization.from_session(session[:authorization])
    end

    def resume_authorization_path
      data = session[:authorization]
      return root_path if data.blank?

      pairs = data.except("resource").compact.to_a
      Array(data["resource"]).each { |value| pairs << [ "resource", value ] }

      "#{authorize_path}?#{URI.encode_www_form(pairs)}"
    end

    def no_such_tenant
      render plain: "no tenant is served at this hostname", status: :not_found
    end

    def policy_denied(denial)
      render json: denial.to_h, status: denial.status
    end
end
