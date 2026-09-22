module Masks
  module Server
    module AvatarsHelper
      def avatar_tag(actor, style: nil, size: 96, **options)
        resolved = style || (Avatars.held?(actor) ? Avatars::PHOTO : Avatars::FALLBACK)
        stamp = Avatars.digest(actor, resolved)

        if stamp.nil?
          resolved = Avatars::FALLBACK
          stamp = Avatars.digest(actor, resolved)
        end

        held = [ "avatar", "avatar-#{resolved}", options.delete(:class) ].compact.join(" ")

        image_tag stamped_avatar_path(actor.uuid, resolved, stamp, size: Avatars.size(size)),
                  width: size, height: size, alt: "", class: held, **options
      end
    end
  end
end
