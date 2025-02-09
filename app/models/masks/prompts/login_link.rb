module Masks
  module Prompts
    class LoginLink
      include Masks::Prompt

      match { client.allow_login_links? && identifier }

      setup do
        prompt = self

        session.structure do
          current :login_link,
                  parent: :entry,
                  expiry: -> { prompt.client.expires_at(:login_link) },
                  null: true
        end
      end

      preauth { session[:login_link] = identifier if identifier }

      postauth always: true do
        entry.login_link = active_login_link
      end

      reset { session.login_link.expire if active_login_link }

      def active_login_link
        @active_login_link ||=
          if session.login_link.data && session.login_link["sent"]
            id = session.login_link["link_id"]

            if id
              Masks::LoginLink.for_login.active.find_by(id:)
            else
              Masks::LoginLink.new(
                client:,
                device:,
                actor:,
                expires_at: session.login_link.expires_at,
              )
            end
          end
      end

      event "login-link:start" do
        unless session.login_link["sent"]
          session.login_link["sent"] = true

          if login_email
            @active_login_link =
              Masks::LoginLink.new(
                log_in: true,
                email: login_email,
                client:,
                device:,
                path:,
                params:,
                expires_at: session.login_link.expires_at,
              )
            @active_login_link.save_and_deliver if active_links&.none?

            session.login_link["link_id"] = @active_login_link.id
          end
        end

        self.prompt = "login-code"
      end

      event "login-link:password" do
        self.prompt = "first-factor"
      end

      event "login-link:verify", if: :active_login_link do
        code = updates["code"] || request.params[:login_code]

        unless active_login_link.code == code
          next warn!("invalid-code", code, prompt: "login-code")
        end

        active_login_link.authenticated!

        session[Entry::FACTOR1] = client.expires_at(:first_factor_login_link)
        session.login_link.expire

        sibling(:reset_password).requested! if updates["resetPassword"]
      end

      prompt "login-link", if: :active_login_link do
        request.GET[:login_link]&.present? && active_login_link
      end

      private

      def login_email
        @login_email ||=
          if actor&.persisted?
            actor.emails.for_login.find_by(address: identifier) ||
              actor.login_email
          end
      end

      def active_links
        @active_links ||=
          if actor&.persisted?
            actor.login_links.active.for_login.where(client:, device:)
          end
      end
    end
  end
end
