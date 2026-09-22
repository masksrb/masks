module Masks
  module Server
    class LoginsController < ApplicationController
      POSTED = %w[code state error error_description user SAMLResponse RelayState].freeze
      POSTED_LIMIT = 256.kilobytes
      POSTED_WINDOW = 5.minutes

      skip_forgery_protection

      rate_limit to: ::Rails.configuration.masks.attempt_limit,
                 within: 3.minutes, only: :update, if: -> { verifying? },
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { too_many("too-many-attempts") }

      rate_limit to: ::Rails.configuration.masks.account_attempt_limit,
                 within: 3.minutes, only: :update, name: "identifier", if: -> { verifying? },
                 by: -> { [ current_tenant.id, login_store["identifier"].to_s.downcase ].join(":") },
                 with: -> { too_many("too-many-attempts-for-account") }

      rate_limit to: ::Rails.configuration.masks.recovery_limit,
                 within: 15.minutes, only: :update, name: "recovery",
                 if: -> { Login.limit_for(params[:event]) == :sending },
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { too_many("too-many-attempts") }

      rate_limit to: ::Rails.configuration.masks.attempt_limit,
                 within: 3.minutes, only: %i[provider posted_provider], name: "provider",
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { too_many("too-many-attempts") }

      before_action :refuse_blocked_agent
      before_action :verify_authenticity_token, except: :posted_provider
      before_action :establish_device, only: %i[update provider]

      def show
        return redirect_to after_login_path if current_actor && pending.nil?

        @login = run
        @login.carry!(flash[:warnings]) if flash[:warnings].present?

        redirect_to after_login_path if @login.settled?
      end

      def update
        login = run(event: params[:event], updates: update_params)

        settle(login) if login.settled? && pending.nil?

        respond_to do |format|
          format.html { resume(login) }
          format.json { render json: serialize(login) }
        end
      end

      def provider
        return link_connection if Linking.pending?(session, callback_params)

        event = LoginStates::Delegation.pending?(login_store, callback_params) ? "delegation:callback" : "provider:callback"
        login = run(event: event, updates: callback_params)

        settle(login) if login.settled? && pending.nil?

        resume(login)
      end

      def posted_provider
        handle = SecureRandom.urlsafe_base64(24)

        ::Rails.cache.write(posted_key(handle), posted_params, expires_in: POSTED_WINDOW)

        redirect_to login_provider_callback_path(params[:key], posted: handle), status: :see_other
      end

      def destroy
        login = run
        login.start_over!
        sign_out

        respond_to do |format|
          format.html { resume(login) }
          format.json { render json: serialize(run) }
        end
      end

      private

        def pending
          return @pending if defined?(@pending)

          @pending = pending_request(resolved_rid)
        end

        def resolved_rid
          @resolved_rid ||= params[:rid].presence ||
            login_store.dig(LoginStates::Provider::HELD, "rid").presence ||
            login_store.dig(LoginStates::Delegation::HELD, "rid").presence
        end

        def callback_params
          @callback_params ||= (params[:posted].present? ? take_posted(params[:posted]) : posted_params)
            .merge("provider" => params[:key].to_s)
        end

        def posted_params
          params.permit(*POSTED).to_h.transform_values { |value| value.to_s[0, POSTED_LIMIT] }
        end

        def take_posted(handle)
          key = posted_key(handle)
          held = ::Rails.cache.read(key)
          ::Rails.cache.delete(key)

          held.is_a?(Hash) ? held.slice(*POSTED) : {}
        end

        def posted_key(handle)
          "provider-callback:#{current_tenant.id}:#{Digest::SHA256.hexdigest(handle.to_s)}"
        end

        def link_connection
          provider = Provider.signing_in.find_by(key: params[:key].to_s)

          connection = Linking.finish!(
            session: session, provider: provider, actor: current_actor, params: callback_params
          )

          redirect_to root_path(anchor: "connections"), notice: t("connections.linked", provider: connection.provider.name)
        rescue Linking::Refused => e
          redirect_to root_path(anchor: "connections"), alert: e.message
        end

        def run(event: nil, updates: {})
          Login.new(
            store: login_store,
            request: pending,
            session: current_session,
            device: current_device,
            rid: resolved_rid,
            event: event,
            updates: updates
          ).update
        end

        def update_params
          params.permit(*Login.permitted_updates).to_h
        end

        def settle(login)
          return unless login.actor

          sign_in(login.actor, amr: login.amr)
          forget_login
        end

        def serialize(login)
          login.as_json.merge("redirectTo" => next_location(login))
        end

        def verifying?
          Login.limit_for(params[:event]) == :verifying
        end

        def resume(login)
          flash[:warnings] = login.carried if login.warnings.any?

          redirect_to next_location(login) || login_path, allow_other_host: true
        end

        def next_location(login)
          return login.redirect_to if login.redirect_to.present?
          return refuse_device(pending) if login.refused? && pending&.device?
          return refuse_saml(pending) if login.refused? && pending&.saml?
          return saml_resume_path(rid: rid_for(pending)) if pending&.saml?
          return deny(pending, login.refusal.error, login.refusal.description) if login.refused? && pending
          return device_url_for(pending) if pending&.device?
          return authorize_url_for(pending) if pending
          return after_login_path if login.settled?

          nil
        end

        def too_many(warning)
          login = run
          login.warn!(warning)

          respond_to do |format|
            format.html { resume(login) }
            format.json { render json: serialize(login), status: :too_many_requests }
          end
        end

        def after_login_path
          pending = latest_handshake
          return handshake_url_for(pending) if pending

          root_path
        end
    end
  end
end
