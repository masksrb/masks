class AvatarsController < ApplicationController
  include RackOAuth2Endpoint
  include ResourceToken
  include ServesPictures

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

    redirect_to root_path, flash: { avatar: t("avatars.updated") }
  rescue Pictures::Unreadable => e
    redirect_to root_path, alert: e.message
  end

  def destroy
    return head :unauthorized if current_actor.nil?

    removed = Avatars.photo(current_actor)&.destroy!

    Event.record!(Event::AVATAR_REMOVED, actor: current_actor) if removed

    redirect_to root_path, flash: { avatar: t("avatars.removed") }
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
      deliver_picture(stamp, cache_control: caching(style, stamp), vary: ("Cookie, Authorization" unless named_style?)) do
        Avatars.render(actor, style, size: Avatars.size(params[:size]))
      end
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

      @bearer = presented_access_token
    end
end
