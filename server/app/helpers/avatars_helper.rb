module AvatarsHelper
  def avatar_tag(actor, style: nil, size: 96, **options)
    resolved = style || (Avatars.held?(actor) ? Avatars::PHOTO : Avatars::FALLBACK)
    stamp = Avatars.digest(actor, resolved)

    image_tag stamped_avatar_path(actor.uuid, resolved, stamp, size: Avatars.size(size)),
              width: size, height: size, alt: "", class: "avatar", **options
  end
end
