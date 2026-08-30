module Masks
  module Rails
    module Authentication
      extend ActiveSupport::Concern

      included do
        helper_method :masks_signed_in?, :masks_identity, :masks_tenant if respond_to?(:helper_method)
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

      def authenticate_masks!
        return true if masks_signed_in?
        return true if masks_tokens && masks_refresh!

        session[:masks_return_to] = request.fullpath if request.get?
        redirect_to Masks::Rails::Engine.routes.url_helpers.start_path
        false
      end
    end
  end
end
