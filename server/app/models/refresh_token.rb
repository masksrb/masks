class RefreshToken < Token
  def self.lifetime
    30.days
  end
end
