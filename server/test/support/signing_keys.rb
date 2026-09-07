module TestSigningKeys
  KEYS = Array.new(4) { OpenSSL::PKey::RSA.generate(SigningKey::SIZE) }.freeze

  class << self
    def next_key
      @cursor = ((@cursor || -1) + 1) % KEYS.size
      KEYS[@cursor]
    end
  end
end

SigningKey.generator = -> { TestSigningKeys.next_key }
