class PendingLogin < Token
  def self.lifetime
    1.day
  end

  def self.open!(store)
    mint!(payload: store)
  end

  def store
    @store ||= (payload || {}).deep_dup
  end

  def keep!(held)
    with_lock do
      update!(payload: held, expires_at: self.class.lifetime.from_now)
    end
  end
end
