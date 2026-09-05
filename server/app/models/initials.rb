class Initials
  CONTENT_TYPE = "image/svg+xml".freeze
  LETTERS = 2
  BOX = 100
  FONT = "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif".freeze

  attr_reader :seed, :letters

  def initialize(seed, *sources)
    @seed = seed.to_s
    @letters = self.class.letters_in(sources)
  end

  def self.letters_in(sources)
    Array(sources).compact_blank.each do |source|
      found = from(source)

      return found if found.present?
    end

    "?"
  end

  def self.from(source)
    words = source.to_s.scan(/[[:alnum:]]+/)

    return "" if words.empty?
    return words.first[0, LETTERS].upcase if words.one?

    "#{words.first[0]}#{words.last[0]}".upcase
  end

  def digest
    @digest ||= Digest::SHA256.hexdigest("initials:#{seed}:#{letters}")[0, 16]
  end

  def to_svg(size = nil)
    side = size || 256

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{side}" height="#{side}" viewBox="0 0 #{BOX} #{BOX}" role="img">
        <rect width="#{BOX}" height="#{BOX}" fill="#{background}"/>
        <text x="50%" y="50%" fill="#{ink}" font-family="#{FONT}" font-size="#{font_size}"
              font-weight="560" letter-spacing="#{spacing}" text-anchor="middle"
              dominant-baseline="central">#{CGI.escape_html(letters)}</text>
      </svg>
    SVG
  end

  private

    def hue
      Digest::SHA256.digest("initials:#{seed}").bytes.last * 360 / 256
    end

    def background
      "hsl(#{hue} 52% 42%)"
    end

    def ink
      "hsl(#{hue} 46% 96%)"
    end

    def font_size
      letters.length > 1 ? 40 : 48
    end

    def spacing
      letters.length > 1 ? 1 : 0
    end
end
