module Avatars
  PHOTO = "photo".freeze
  IDENTICON = "identicon".freeze
  INITIALS = "initials".freeze

  STYLES = [ PHOTO, IDENTICON, INITIALS ].freeze
  GENERATED = [ IDENTICON, INITIALS ].freeze
  FALLBACK = IDENTICON
  SIZES = [ 32, 64, 128, 256, 512 ].freeze

  class << self
    def style?(value)
      STYLES.include?(value.to_s)
    end

    def generated?(value)
      GENERATED.include?(value.to_s)
    end

    def size(value)
      return nil if value.blank?

      SIZES.find { |allowed| allowed >= value.to_i } || SIZES.last
    end

    def photo(actor)
      Avatar.find_by(actor_id: actor.id)
    end

    def identicon(actor)
      Identicon.new(actor.uuid)
    end

    def initials(actor)
      Initials.new(actor.uuid, actor.name, actor.nickname, actor.email&.split("@")&.first)
    end

    def held?(actor)
      photo(actor).present?
    end

    def digest(actor, style)
      case style.to_s
      when PHOTO then photo(actor)&.digest
      when IDENTICON then identicon(actor).digest
      when INITIALS then initials(actor).digest
      end
    end

    def render(actor, style, size: nil)
      case style.to_s
      when PHOTO then rendered_photo(actor, size)
      when IDENTICON then [ Identicon::CONTENT_TYPE, identicon(actor).to_svg(size) ]
      when INITIALS then [ Initials::CONTENT_TYPE, initials(actor).to_svg(size) ]
      end
    end

    def url(actor, style, subject:, origin: Current.origin, size: nil)
      return nil if origin.blank?

      held = digest(actor, style)
      return nil if held.nil?

      query = size ? "?size=#{size}" : ""

      "#{origin}/avatars/#{subject}/#{style}/#{held}#{query}"
    end

    def urls(actor, subject:, origin: Current.origin)
      return nil if origin.blank?

      {
        PHOTO => (url(actor, PHOTO, subject: subject, origin: origin) if held?(actor)),
        IDENTICON => url(actor, IDENTICON, subject: subject, origin: origin),
        INITIALS => url(actor, INITIALS, subject: subject, origin: origin)
      }
    end

    def picture(actor, subject:, origin: Current.origin)
      return actor.picture_url if actor.picture_url.present?

      url(actor, held?(actor) ? PHOTO : FALLBACK, subject: subject, origin: origin)
    end

    private

      def rendered_photo(actor, size)
        held = photo(actor)

        return nil if held.nil?

        [ held.content_type, held.resized(size) ]
      end
  end
end
