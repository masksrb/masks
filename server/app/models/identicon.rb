class Identicon
  CONTENT_TYPE = "image/svg+xml".freeze
  CELLS = 5
  HALF = (CELLS + 1) / 2
  MARGIN = 1
  BOX = CELLS + (MARGIN * 2)

  attr_reader :seed

  def initialize(seed)
    @seed = seed.to_s
  end

  def digest
    @digest ||= Digest::SHA256.hexdigest("identicon:#{seed}")[0, 16]
  end

  def to_svg(size = nil)
    side = size || 256

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="#{side}" height="#{side}" viewBox="0 0 #{BOX} #{BOX}" role="img">
        <rect width="#{BOX}" height="#{BOX}" fill="#{background}"/>
        #{squares}
      </svg>
    SVG
  end

  private

    def bytes
      @bytes ||= Digest::SHA256.digest("identicon:#{seed}").bytes
    end

    def hue
      bytes[-1] * 360 / 256
    end

    def foreground
      "hsl(#{hue} 58% 48%)"
    end

    def background
      "hsl(#{hue} 44% 95%)"
    end

    def squares
      filled.map do |column, row|
        %(<rect x="#{column + MARGIN}" y="#{row + MARGIN}" width="1" height="1" fill="#{foreground}"/>)
      end.join("\n    ")
    end

    def filled
      cells = []

      HALF.times do |column|
        CELLS.times do |row|
          next unless bytes[(column * CELLS) + row].even?

          cells << [ column, row ]
          cells << [ CELLS - 1 - column, row ] unless column == CELLS - 1 - column
        end
      end

      cells
    end
end
