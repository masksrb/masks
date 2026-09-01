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

        pending = masks_requests.open(
          return_to: requested_return_to || session.delete(:masks_return_to)
        )
        started = masks_session.start(
          state: pending.id,
          resource: masks_config.resource_for(request)
        )

        masks_requests.amend(
          pending.id, nonce: started[:nonce], verifier: started[:verifier]
        )

        redirect_to started[:url], allow_other_host: true
      end

      def callback
        pending = masks_requests.claim(params[:state])

        return stale if pending.nil?
        return refuse(params[:error], params[:error_description], pending) if params[:error].present?

        tokens = masks_session.complete(
          code: params[:code],
          verifier: pending[:verifier],
          resource: masks_config.resource_for(request)
        )

        identity = begin
          masks_identity_from(tokens)
        rescue Masks::Client::InvalidToken
          :unverified
        end

        unless nonce_matches?(identity, pending[:nonce])
          return refuse("invalid_nonce", "the id token was issued for another request", pending)
        end

        masks_store(tokens, identity: identity)

        redirect_to pending[:return_to] || masks_config.after_sign_in
      rescue Masks::Client::Error => e
        refuse(e.class.name.demodulize.underscore, e.message, pending)
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

        def nonce_matches?(identity, sent)
          return false if identity == :unverified
          return true if sent.blank?
          return false unless identity.is_a?(Hash)

          held = identity["nonce"].to_s
          held.present? && ActiveSupport::SecurityUtils.secure_compare(held, sent)
        end

        def stale
          answer(
            "invalid_state",
            "that sign-in request is not one this browser started, or it expired",
            :bad_request
          )
        end

        def refuse(code, description, pending = nil)
          masks_forget if pending

          answer(code, description, :bad_request)
        end

        def answer(code, description, status)
          if masks_wants_json?
            render json: { "error" => code, "error_description" => description }, status: status
          else
            render plain: "sign-in failed — #{code}: #{description}", status: status
          end
        end
    end
  end
end
