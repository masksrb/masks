module Masks
  module Rails
    module Authentication
      extend ActiveSupport::Concern
      include Masks::Rails::Configurable
      include Masks::Rails::Privileged

      included do
        if respond_to?(:helper_method)
          helper_method :masked, :masks_login_url
        end
      end

      REQUESTS = "masks_requests".freeze
      HANDSHAKES = "masks_handshakes".freeze
      FAREWELLS = "masks_farewells".freeze
      STEPPED_UP = "masks_stepped_up".freeze
      STEP_UP_WITHIN = 300

      def masks_session
        @masks_session ||= masks_config.session_for(request)
      end

      def masks_requests
        @masks_requests ||= masks_tracker(REQUESTS)
      end

      def masks_handshakes
        @masks_handshakes ||= masks_tracker(HANDSHAKES)
      end

      def masks_farewells
        masks_tracker(FAREWELLS)
      end

      def masks_tracker(key)
        Masks::Client::Tracker.new(Masks::Client::Stores::Session.new(session, key))
      end

      def masks_tokens
        return @masks_tokens if defined?(@masks_tokens)

        held = masks_held

        if held.present? && masks_departed?(held)
          masks_forget
          return nil
        end

        @masks_tokens = Masks::Client::Tokens.from_h(held)
      end

      def masks_cache
        @masks_cache ||= Masks::Rails::Cache.new(masks_config.cache)
      end

      def masks_store(tokens, identity: nil)
        held = tokens.to_h.except("id_token")
        held.delete("token_type") if held["token_type"] == "Bearer"
        held["identity"] = identity&.slice(*IDENTITY) || masks_held["identity"]
        held["signed_in_at"] = masks_held["signed_in_at"] || Masks::Rails::Cache.now

        masks_session_cookies.write(held.compact)
        @masks_held = held.compact
        @masks_tokens = tokens
        @masked = nil
      end

      def masks_held
        @masks_held ||= masks_session_cookies.read || {}
      end

      def masks_session_cookies
        Masks::Rails::SessionCookies.new(request, masks_config.session_key)
      end

      IDENTITY = [
        "sub", "sid", "name", "preferred_username", "email", "email_verified", "tenant",
        "picture", Masks::Client::Claims::AVATARS, Masks::Client::Claims::ORGANIZATION,
        Masks::Client::Claims::ORGANIZATIONS
      ].freeze

      def masks_identity_from(tokens)
        return nil if tokens.id_token.nil?

        masks_session.identity(tokens)
      end

      def masks_forget
        masks_session_cookies.clear
        @masks_held = {}
        @masks_tokens = nil
        @masked = nil
      end

      def masked
        @masked ||= if masks_tokens
          Masked.new(
            claims: Masks::Client::Claims.new(masks_held["identity"] || {}), scopes: masks_tokens.scopes,
            config: masks_config, signed_in: masks_signed_in?, access_token: masks_tokens.access_token,
            expires_at: masks_tokens.expires_at, account_url: masks_account_url
          )
        else
          Masked.nobody(masks_config)
        end
      end

      def masks_signed_in?
        masks_tokens.present? && !masks_tokens.expired?
      end

      def masks_configured?
        masks_config.configured?(request)
      end

      def masks_registration
        Masks::Client::Registration.held(
          masks_config.issuer_for(request),
          masks_config.credentials_for(request)
        )
      end

      def masks_registered?
        held = masks_registration

        held.nil? || held.known?
      rescue Masks::Client::Error
        true
      end

      def masks_disconnect!
        return false unless masks_configured? && masks_config.can_forget?

        masks_config.forget!(request)
        masks_forget

        true
      end

      def masks_reconnect!
        return false if masks_registered?

        masks_disconnect!
      end

      def masks_handshake_path
        Masks::Rails::Engine.routes.url_helpers.handshake_path
      end

      def masks_refresh!
        return false unless masks_configured? && masks_tokens

        spent = masks_tokens.refresh_token

        if spent.nil?
          masks_forget
          return false
        end

        renewal = masks_cache.renew(masks_config.issuer_for(request).to_s, spent) { masks_renewal(spent) }

        case renewal.outcome
        when :renewed
          masks_store(renewal.tokens, identity: renewal.identity)
          true
        when :unregistered
          masks_disconnect!
          false
        when :refused
          masks_forget
          false
        else
          false
        end
      end

      def masks_refreshed_identity(tokens)
        held = masks_held["identity"]

        return nil unless held.is_a?(Hash)

        profile = masks_session.profile(tokens)

        return nil if profile.empty? || profile["sub"].to_s != held["sub"].to_s

        held.merge(profile.slice(*IDENTITY))
      end

      def masks_login_url(return_to: nil, organization: nil, privilege: nil)
        path = Masks::Rails::Engine.routes.url_helpers.start_path
        query = {
          "return_to" => masks_local_path(return_to),
          "organization" => Masks::Client::Session.organization_key(organization),
          "privilege" => Array(privilege).join(" ").presence
        }.compact

        query.empty? ? path : "#{path}?#{URI.encode_www_form(query)}"
      end

      def masks_account_url
        "#{masks_config.issuer_for(request).to_s.chomp('/')}/"
      rescue Masks::Rails::Configuration::Unconfigured
        nil
      end

      def authenticate_masks!
        return true if masks_configured? && (masks_signed_in? || (masks_tokens && masks_refresh!))

        masks_refuse
        false
      end

      private

        def masks_departed?(held)
          identity = held["identity"]

          return false unless identity.is_a?(Hash)

          masks_cache.departed?(masks_config.issuer_for(request).to_s, identity, since: held["signed_in_at"].to_i)
        rescue Masks::Rails::Configuration::Unconfigured
          false
        end

        def masks_renewal(spent)
          refreshed = masks_session.refresh(spent, resource: masks_config.resource_for(request))
          refreshed = Masks::Client::Tokens.from_h(refreshed.to_h.merge("refresh_token" => spent)) if refreshed.refresh_token.nil?

          Masks::Rails::Renewal.renewed(refreshed, masks_refreshed_identity(refreshed))
        rescue Masks::Client::Unregistered
          Masks::Rails::Renewal.unregistered
        rescue Masks::Client::Rejected => e
          e.status.to_i >= 500 || e.status.to_i == 429 ? Masks::Rails::Renewal.unreachable : Masks::Rails::Renewal.refused
        rescue Masks::Client::Error
          Masks::Rails::Renewal.unreachable
        end

        def masks_sign_out_upstream
          return nil unless masks_configured?

          farewell = masks_farewells.open

          masks_session.end_session_url(
            post_logout_redirect_uri: masks_config.post_logout_redirect_uri_for(request),
            state: farewell.id
          )
        rescue Masks::Client::Error
          masks_farewells.clear!
          nil
        end

        def masks_after_sign_out_path
          masks_local_path(masks_config.after_sign_out) || "/"
        end

        def masks_authorize_session!(wanted)
          return false unless authenticate_masks!

          wanted.each { |privilege| masked.member!(privilege) }

          missing = wanted.reject { |privilege| (privilege.scopes - masked.scopes).empty? }.map(&:name)
          return true if missing.empty?

          if masks_asked_already?(session.delete(STEPPED_UP), missing)
            raise Masks::Client::Forbidden.new(
              "insufficient_scope", "this account does not hold the #{missing.join(' and ')} privilege",
              scope: missing.flat_map { |name| masks_config.privilege(name).scopes }.join(" ")
            )
          end

          masks_ask_again(missing)
          false
        rescue Masks::Client::Forbidden => e
          masks_forbid(e)
          false
        end

        def masks_asked_already?(asked, missing)
          asked.is_a?(Hash) && (missing - Array(asked["privileges"])).empty? &&
            asked["at"].to_i > Time.now.to_i - STEP_UP_WITHIN
        end

        def masks_ask_again(missing)
          return_to = request.get? ? request.fullpath : masks_referring_path
          url = masks_login_url(return_to: return_to, privilege: missing)

          session[STEPPED_UP] = { "privileges" => missing, "at" => Time.now.to_i }

          if masks_wants_json?
            response.headers["Cache-Control"] = "no-store"
            render json: { "error" => "privilege_required", "privileges" => missing, "login_url" => url },
                   status: :forbidden
          else
            redirect_to url
          end
        end

        def masks_forbid(error)
          response.headers["Cache-Control"] = "no-store"

          if masks_wants_json?
            render json: { "error" => error.code, "error_description" => error.description }, status: :forbidden
          else
            render plain: error.description, status: :forbidden
          end
        end

        def masks_refuse
          return masks_refuse_json if masks_wants_json?
          return redirect_to(masks_handshake_path) unless masks_configured?

          session[:masks_return_to] = request.fullpath if request.get?
          redirect_to Masks::Rails::Engine.routes.url_helpers.start_path
        end

        def masks_refuse_json
          response.headers["Cache-Control"] = "no-store"

          render json: masks_refusal, status: :unauthorized
        end

        def masks_refusal
          unless masks_configured?
            return {
              "signed_in" => false,
              "error" => "handshake_required",
              "handshake_url" => masks_handshake_path
            }
          end

          {
            "signed_in" => false,
            "error" => "login_required",
            "login_url" => masks_login_url(return_to: masks_referring_path)
          }
        end

        def masks_wants_json?
          request.xhr? ||
            request.format.json? ||
            request.content_mime_type&.symbol == :json ||
            !request.format.html?
        end

        def masks_referring_path
          return nil if request.referer.blank?

          masks_local_path(URI.parse(request.referer).request_uri)
        rescue URI::InvalidURIError
          nil
        end

        def masks_local_path(value)
          path = value.to_s

          return nil unless path.start_with?("/")
          return nil if path.match?(/[\x00-\x20\x7f\\]/)

          uri = URI.parse(path)

          return nil if uri.scheme || uri.host || uri.userinfo || !uri.path.start_with?("/") || uri.path.start_with?("//")

          [ uri.path, uri.query ].compact.join("?")
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
