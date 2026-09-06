class ApplicationController < ActionController::Base
  class TenantMissing < StandardError; end

  REQUESTS = "requests".freeze
  HANDSHAKES = "handshakes".freeze
  TRACKED = 5

  around_action :in_locale
  around_action :within_tenant
  before_action :withhold_referrer
  before_action :refuse_blocked_device

  helper_method :current_actor, :current_tenant, :current_device, :hid_for

  rescue_from TenantMissing, with: :no_such_tenant
  rescue_from Policy::Denied, with: :policy_denied

  private

    def current_tenant
      @current_tenant ||=
        Tenant.resolve(request.host) || Tenant.claim(request.host) || raise(TenantMissing)
    end

    def withhold_referrer
      response.headers["Referrer-Policy"] = "same-origin"
    end

    def in_locale
      locale = Locales.negotiate(request.headers["Accept-Language"])

      I18n.with_locale(locale) { yield }

      response.headers["Content-Language"] = Locales.tag(locale)
      response.headers["Vary"] =
        [ response.headers["Vary"].presence, "Accept-Language" ].compact.join(", ")
    end

    def within_tenant
      Current.origin = origin
      Current.ip_address = request.remote_ip
      Current.user_agent = request.user_agent

      Tenant.switch(current_tenant) { yield }
    end

    def origin
      template = Rails.configuration.masks.public_origin_template
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

    def current_device
      return @current_device if defined?(@current_device)

      held = cookies.signed[Device::COOKIE].presence

      @current_device = held && recognise(held)
    end

    def establish_device
      @current_device = recognise(cookies.signed[Device::COOKIE].presence)
    end

    def refuse_blocked_device
      return unless current_device&.blocked?

      render plain: "this device has been blocked", status: :forbidden
    end

    def recognise(public_id)
      device = Device.identify(
        public_id,
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      )

      cookies.signed[Device::COOKIE] = {
        value: device.public_id,
        expires: Device::LIFETIME.from_now,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }

      Current.device = device
    end

    def sign_in(actor, amr: [])
      carried = session.to_hash.slice(REQUESTS, HANDSHAKES, "login", "masks_return_to")
      reset_session
      carried.each { |key, value| session[key] = value }

      device = establish_device

      record = Session.start!(
        actor: actor,
        device: device,
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
        amr: amr
      )

      cookies.encrypted[:masks_session] = {
        value: record.secret,
        expires: record.expires_at,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }

      actor.update!(last_login_at: Time.current)

      Event.record!(Event::SESSION_STARTED, actor: actor, device: device, amr: amr.presence)

      @current_session = record
    end

    def sign_out
      ended = current_session

      ended&.revoke!
      cookies.delete(:masks_session)
      @current_session = nil

      Event.record!(Event::SESSION_ENDED, actor: ended.actor) if ended
    end

    def tracked(key)
      session[key] ||= {}
    end

    def track!(key, model, subject)
      held = tracked(key)[subject.fingerprint]
      existing = held && model.spent(held)

      return existing if existing&.live?
      return existing if existing&.consumed? && model.answered_is_final?

      opened = model.open!(subject)
      session[key] = tracked(key).merge(subject.fingerprint => opened.secret).to_a.last(TRACKED).to_h

      opened
    end

    def id_for(key, pending)
      tracked(key)[pending.fingerprint] || pending.secret
    end

    def pending_for(key, model, id)
      return nil if id.blank?
      return nil unless tracked(key).value?(id)

      model.redeem(id)
    end

    def track_request!(authorization)
      track!(REQUESTS, PendingRequest, authorization)
    end

    def rid_for(pending)
      id_for(REQUESTS, pending)
    end

    def pending_request(rid)
      pending_for(REQUESTS, PendingRequest, rid)
    end

    def track_handshake!(handshake)
      track!(HANDSHAKES, PendingHandshake, handshake)
    end

    def hid_for(pending)
      id_for(HANDSHAKES, pending)
    end

    def pending_handshake(hid)
      pending_for(HANDSHAKES, PendingHandshake, hid)
    end

    def latest_handshake
      held = tracked(HANDSHAKES).values.last

      held && PendingHandshake.redeem(held)
    end

    def handshake_url_for(pending)
      "#{handshake_path}?#{URI.encode_www_form(pending.handshake.query_pairs)}"
    end

    def deny(pending, error, description)
      PendingRequest.claim(rid_for(pending))

      pending.authorization.redirect_with(
        issuer: issuer, error: error, error_description: description
      )
    end

    def authorize_url_for(pending)
      "#{authorize_path}?#{URI.encode_www_form(pending.authorization.query_pairs)}"
    end

    def no_such_tenant
      render plain: "no tenant is served at this hostname", status: :not_found
    end

    def policy_denied(denial)
      render json: denial.to_h, status: denial.status
    end
end
