module AvatarsHelper
  def avatar_tag(actor, style: nil, size: 96, **options)
    resolved = style || (Avatars.held?(actor) ? Avatars::PHOTO : Avatars::FALLBACK)
    stamp = Avatars.digest(actor, resolved)

    # Asking for a photo an actor does not have leaves nothing to stamp, and a
    # path with no digest cannot be built at all. Fall back rather than raise.
    if stamp.nil?
      resolved = Avatars::FALLBACK
      stamp = Avatars.digest(actor, resolved)
    end

    image_tag stamped_avatar_path(actor.uuid, resolved, stamp, size: Avatars.size(size)),
              width: size, height: size, alt: "", class: "avatar", **options
  end
end
