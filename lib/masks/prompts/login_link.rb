module Masks
  module Prompts
    class LoginLink
      include Masks::Prompt

      setting :email_code,
              :string,
              default: -> { session.rails_request.params[:login_link] }
      setting :reset_password, :boolean

      match { current_client.allow_login_links? && on_first_factor? }

      setup do
        client = current_client

        session.structure do
          current :login_link,
                  parent: :endpoint,
                  expiry: -> { client.expires_at(:email_login) },
                  null: true
        end
      end

      preauth do
        session[:login_link] = current_identifier if current_identifier
      end

      postauth always: true do
        login.login_link = active_login_link
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
                client: current_client,
                device: current_device,
                actor: current_actor,
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
                client: current_client,
                device: current_device,
                url: session.rails_request.url,
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
        unless active_login_link.code == email_code
          next warn!("invalid-code", email_code, prompt: "login-code")
        end

        active_login_link.authenticated!

        session[Prompt::FACTOR1] = current_client.expires_at(:email_login)
        session.login_link.expire

        sibling(:reset_password).requested! if reset_password?
      end

      prompt "login-link", if: :active_login_link do
        request.GET[:login_link]&.present? && active_login_link
      end

      private

      def login_email
        @login_email ||=
          if current_actor&.persisted?
            current_actor.emails.for_login.find_by(
              address: current_identifier,
            ) || current_actor.login_email
          end
      end

      def active_links
        @active_links ||=
          if current_actor&.persisted?
            current_actor.login_links.active.for_login.where(
              client: current_client,
              device: current_device,
            )
          end
      end
    end
  end
end
