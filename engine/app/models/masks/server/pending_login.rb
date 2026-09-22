module Masks
  module Server
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
        return if held == payload && expires_at > (self.class.lifetime / 2).from_now

        update_columns(payload: held, expires_at: self.class.lifetime.from_now, updated_at: Time.current)
      end
    end
  end
end
