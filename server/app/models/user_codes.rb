module UserCodes
  ALPHABET = "BCDFGHJKLMNPQRSTVWXZ".chars.freeze
  LENGTH = 8
  GROUP = 4

  class << self
    def generate
      Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
    end

    def spaced(code)
      code.to_s.scan(/.{1,#{GROUP}}/).join("-")
    end

    def read(value)
      held = value.to_s.upcase.gsub(/[^A-Z]/, "")

      return nil unless held.length == LENGTH
      return nil unless held.chars.all? { |letter| ALPHABET.include?(letter) }

      held
    end

    def digest(code)
      Digest::SHA256.hexdigest(code.to_s)
    end
  end
end
