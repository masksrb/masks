module Masks
  module Rails
    class SessionsController < BaseController
      def show
        if masks_configured? && (masks_signed_in? || (masks_tokens && masks_refresh!))
          response.headers["Cache-Control"] = "no-store"

          render json: masks_account
        else
          masks_forget
          masks_refuse_json
        end
      end

      def start
        return redirect_to(masks_handshake_path) unless masks_configured?

        started = masks_session.start(resource: masks_config.resource_for(request))

        session[:masks_state] = started[:state]
        session[:masks_nonce] = started[:nonce]
        session[:masks_verifier] = started[:verifier]
        session[:masks_return_to] = requested_return_to || session[:masks_return_to]

        redirect_to started[:url], allow_other_host: true
      end

      def callback
        return refuse(params[:error], params[:error_description]) if params[:error].present?
        return refuse("invalid_state", "the callback did not match this browser") unless state_matches?

        tokens = masks_session.complete(
          code: params[:code],
          verifier: session.delete(:masks_verifier),
          resource: masks_config.resource_for(request)
        )

        identity = begin
          masks_identity_from(tokens)
        rescue Masks::Client::InvalidToken
          :unverified
        end

        return refuse("invalid_nonce", "the id token was issued for another request") unless nonce_matches?(identity)

        masks_store(tokens, identity: identity)
        session.delete(:masks_state)
        session.delete(:masks_nonce)

        redirect_to session.delete(:masks_return_to) || masks_config.after_sign_in
      rescue Masks::Client::Error => e
        refuse(e.class.name.demodulize.underscore, e.message)
      end

      def destroy
        everywhere = masks_config.sign_out_of_issuer || params[:everywhere].present?
        upstream = everywhere ? masks_logout_url : nil

        masks_forget

        if masks_wants_json?
          render json: { "signed_in" => false, "logout_url" => upstream }.compact
        else
          redirect_to upstream || masks_config.after_sign_out, allow_other_host: upstream.present?
        end
      end

      private

        def requested_return_to
          masks_local_path(params[:return_to])
        end

        def state_matches?
          expected = session[:masks_state]
          expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
        end

        def nonce_matches?(identity)
          return false if identity == :unverified

          sent = session[:masks_nonce]
          return true if sent.blank?
          return false unless identity.is_a?(Hash)

          held = identity["nonce"].to_s
          held.present? && ActiveSupport::SecurityUtils.secure_compare(held, sent)
        end

        def refuse(code, description)
          masks_forget

          if masks_wants_json?
            render json: { "error" => code, "error_description" => description },
                   status: :bad_request
          else
            render plain: "sign-in failed — #{code}: #{description}", status: :bad_request
          end
        end
    end
  end
end
