module Masks
  module Server
    class Isolation
      HELD = %w[
        rack.session rack.session.options action_dispatch.cookies
        action_dispatch.key_generator action_dispatch.secret_key_base
        action_dispatch.cookies_rotations
      ].freeze

      SESSION_KEY = "_masks_session".freeze

      def initialize(app)
        store = ActionDispatch::Session::CookieStore.new(
          app, key: SESSION_KEY, httponly: true, same_site: :lax, secure: !::Rails.env.local?
        )
        @app = ActionDispatch::Cookies.new(store)
      end

      def call(env)
        held = HELD.to_h { |key| [ key, env[key] ] }
        HELD.each { |key| env.delete(key) }

        env["action_dispatch.key_generator"] = Server.key_generator
        env["action_dispatch.secret_key_base"] = Server.secret_key_base
        env["action_dispatch.cookies_rotations"] = ActiveSupport::Messages::RotationConfiguration.new

        @app.call(env)
      ensure
        HELD.each { |key| env.delete(key) }
        held.each { |key, value| env[key] = value unless value.nil? }
      end
    end
  end
end
