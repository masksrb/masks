module Masks
  module Rails
    module Authentication
      extend ActiveSupport::Concern

      included do
        if respond_to?(:helper_method)
          helper_method :masks_signed_in?, :masks_identity, :masks_tenant, :masks_scopes
        end
      end

      def masks_config
        Masks::Rails.config
      end

      def masks_session
        @masks_session ||= masks_config.session_for(request)
      end

      def masks_tokens
        return @masks_tokens if defined?(@masks_tokens)

        @masks_tokens = Masks::Client::Tokens.from_h(session[masks_config.session_key])
      end

      def masks_store(tokens)
        session[masks_config.session_key] = tokens.to_h
        @masks_tokens = tokens
      end

      def masks_forget
        session.delete(masks_config.session_key)
        @masks_tokens = nil
        @masks_identity = nil
      end

      def masks_signed_in?
        masks_tokens.present? && !masks_tokens.expired?
      end

      def masks_identity
        return @masks_identity if defined?(@masks_identity)

        @masks_identity = masks_tokens && masks_session.identity(masks_tokens)
      rescue Masks::Client::InvalidToken
        @masks_identity = nil
      end

      def masks_tenant
        masks_identity&.dig("tenant")
      end

      def masks_scopes
        masks_tokens&.scopes || []
      end

      def masks_permits?(scope)
        masks_scopes.include?(scope.to_s)
      end

      def masks_access_token
        masks_tokens&.access_token
      end

      def masks_refresh!
        return false if masks_tokens&.refresh_token.nil?

        masks_store(
          masks_session.refresh(
            masks_tokens.refresh_token,
            resource: masks_config.resource_for(request)
          )
        )
        true
      rescue Masks::Client::Rejected
        masks_forget
        false
      end

      def masks_login_url(return_to: nil)
        path = Masks::Rails::Engine.routes.url_helpers.start_path
        target = masks_local_path(return_to)

        target ? "#{path}?return_to=#{CGI.escape(target)}" : path
      end

      def masks_account
        identity = masks_identity || {}

        {
          "signed_in" => masks_signed_in?,
          "subject" => identity["sub"],
          "name" => identity["name"],
          "nickname" => identity["preferred_username"],
          "email" => identity["email"],
          "email_verified" => identity["email_verified"],
          "tenant" => masks_tenant,
          "scopes" => masks_scopes,
          "expires_at" => masks_tokens&.expires_at
        }.compact
      end

      def authenticate_masks!
        return true if masks_signed_in?
        return true if masks_tokens && masks_refresh!

        masks_refuse
        false
      end

      private

        def masks_refuse
          return masks_refuse_json if masks_wants_json?

          session[:masks_return_to] = request.fullpath if request.get?
          redirect_to Masks::Rails::Engine.routes.url_helpers.start_path
        end

        def masks_refuse_json
          response.headers["Cache-Control"] = "no-store"

          render json: {
            "signed_in" => false,
            "error" => "login_required",
            "login_url" => masks_login_url(return_to: masks_referring_path)
          }, status: :unauthorized
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
          return nil if path.start_with?("//", "/\\")

          path
        end
    end
  end
end
