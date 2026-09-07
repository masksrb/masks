class AvatarsController < ApplicationController
  SEALED = "default-src 'none'; sandbox".freeze
  FOREVER = 1.year.to_i
  BRIEFLY = 5.minutes.to_i

  skip_before_action :refuse_blocked_device, only: :show

  def show
    actor = Subjects.locate(params[:uuid])

    return head :not_found if actor.nil?

    style = requested_style(actor)

    return head :not_found if style.nil?
    return refuse_photo if style == Avatars::PHOTO && !may_see_photo?(actor)

    stamp = Avatars.digest(actor, style)

    return head :not_found if stamp.nil?
    return redirect_to stamped_avatar_path(params[:uuid], style, stamp, **size_param) if stale?(stamp)

    deliver(actor, style, stamp)
  end

  def create
    return head :unauthorized if current_actor.nil?

    Avatar.store!(actor: current_actor, upload: params[:avatar])

    Event.record!(Event::AVATAR_UPLOADED, actor: current_actor)

    redirect_to root_path(anchor: "avatar"), notice: t("avatars.updated")
  rescue Avatar::Unreadable => e
    redirect_to root_path(anchor: "avatar"), alert: e.message
  end

  def destroy
    return head :unauthorized if current_actor.nil?

    removed = Avatars.photo(current_actor)&.destroy!

    Event.record!(Event::AVATAR_REMOVED, actor: current_actor) if removed

    redirect_to root_path(anchor: "avatar"), notice: t("avatars.removed")
  end

  private

    def requested_style(actor)
      asked = params[:style].presence

      return fallback_for(actor) if asked.nil?
      return nil unless Avatars.style?(asked)

      asked
    end

    def fallback_for(actor)
      return Avatars::FALLBACK unless Avatars.held?(actor) && may_see_photo?(actor)

      Avatars::PHOTO
    end

    def stale?(stamp)
      params[:digest].present? && params[:digest] != stamp
    end

    def size_param
      held = params[:size].presence

      held ? { size: held } : {}
    end

    def deliver(actor, style, stamp)
      content_type, bytes = Avatars.render(actor, style, size: Avatars.size(params[:size]))

      return head :not_found if bytes.nil?

      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = SEALED
      response.headers["Cache-Control"] = caching(style, stamp)
      response.headers["Vary"] = "Cookie, Authorization" unless named_style?
      response.headers["ETag"] = %("#{stamp}")

      return head :not_modified if request.headers["If-None-Match"].to_s.include?(stamp)

      send_data bytes, type: content_type, disposition: "inline"
    end

    def named_style?
      params[:style].present?
    end

    def caching(style, stamp)
      shared = named_style? && Avatars.generated?(style) ? "public" : "private"
      age = params[:digest] == stamp ? FOREVER : BRIEFLY
      immutable = params[:digest] == stamp ? ", immutable" : ""

      "#{shared}, max-age=#{age}#{immutable}"
    end

    def may_see_photo?(actor)
      return true if current_actor&.id == actor.id
      return true if current_actor&.holds?(Scopes::MANAGE)
      return false if bearer.nil?
      return true if bearer.scope_list.include?(Scopes::MANAGE)

      bearer.actor_id == actor.id && bearer.scope_list.include?(Scopes::PROFILE)
    end

    def refuse_photo
      response.headers["WWW-Authenticate"] =
        %(Bearer realm="#{issuer.url}", scope="#{Scopes::PROFILE}")

      head :unauthorized
    end

    def bearer
      return @bearer if defined?(@bearer)

      header = request.authorization.to_s

      @bearer = header.start_with?("Bearer ") ? verified(header.split(" ", 2).last) : nil
    end

    def verified(secret)
      claims = JWT.decode(
        secret, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: issuer.jwks,
        iss: issuer.url, verify_iss: true,
        verify_expiration: true,
        required_claims: %w[iss sub exp jti]
      ).first

      AccessToken.live.find_by(digest: claims["jti"])
    rescue JWT::DecodeError
      nil
    end
end
