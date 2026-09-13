class RefreshToken < Token
  def self.lifetime
    30.days
  end

  def revoke!
    transaction do
      super + root.lineage.select { |token| token.is_a?(AccessToken) }.sum(&:revoke!)
    end
  end
end
