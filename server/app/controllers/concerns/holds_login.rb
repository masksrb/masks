module HoldsLogin
  extend ActiveSupport::Concern

  LOGIN = "login".freeze

  included do
    after_action :keep_login
  end

  private

    def login_store
      return @login_store if defined?(@login_store)

      @login_secret = session[LOGIN]
      @pending_login = PendingLogin.redeem(@login_secret)
      @login_store = @pending_login ? @pending_login.store : {}
    end

    def replace_login(held)
      login_store.replace(held)
    end

    def forget_login
      login_store
      @login_store = {}
      keep_login
    end

    def keep_login
      return unless defined?(@login_store)

      if @login_store.empty?
        @pending_login&.destroy
        @pending_login = nil
        session.delete(LOGIN)
      elsif @pending_login
        @pending_login.keep!(@login_store)
        session[LOGIN] = @login_secret
      else
        @pending_login = PendingLogin.open!(@login_store)
        session[LOGIN] = @pending_login.secret
      end
    end
end
