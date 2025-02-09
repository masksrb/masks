module Masks
  class SessionStore < ActiveRecord::SessionStore::Session
    self.abstract_class = true

    if Masks.conf.db.enabled?(:sessions)
      connects_to database: { writing: :sessions }
    end
  end

  class SessionRecord < SessionStore
    include Cleanable

    cleanup :updated_at do
      Masks.conf.duration(:session_inactive)
    end

    class << self
      def expire_after
        Masks.conf.duration(:session_cookie_lifetime)
      end
    end
  end
end
