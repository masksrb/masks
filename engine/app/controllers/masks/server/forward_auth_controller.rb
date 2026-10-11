module Masks
  module Server
    class ForwardAuthController < ApplicationController
      skip_forgery_protection
      before_action -> { request.session_options[:skip] = true }, only: %i[check callback]

      rate_limit to: 30, within: 1.minute, only: %i[start callback],
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { head :too_many_requests }

      def check
        target = Forwarded.target(request)
        return head(:bad_request) if target.nil?
        return answer_callback(target, params_from(target)["code"]) if target.path == Client::FORWARD_CALLBACK

        client = Client.forwarding_to(target)
        return head(:forbidden) if client.nil?

        held = ForwardSession.held(cookies[ForwardSession::COOKIE], client)
        return admit(held.actor) if held

        return head(:unauthorized) if params[:status] == "401"

        redirect_to forward_auth_start_url(rd: target.to_s), allow_other_host: true
      end

      def start
        target = URI.parse(return_to)
        client = Client.forwarding_to(target)

        return render(plain: t("forward_auth.unknown"), status: :not_found) if client.nil?
        return redirect_to(login_path(return_to: request.fullpath)) if current_actor.nil?
        return render(plain: t("forward_auth.not_admitted", app: client.name), status: :forbidden) unless client.admits?(current_actor)

        code = ForwardCode.mint!(actor: current_actor, client: client, session: current_session,
                                 payload: { "return_to" => target.to_s })

        redirect_to "#{client.forward_origin}#{Client::FORWARD_CALLBACK}?code=#{code.secret}", allow_other_host: true
      rescue URI::InvalidURIError
        render plain: t("forward_auth.unknown"), status: :not_found
      end

      def callback
        target = Forwarded.target(request)
        return head(:bad_request) if target.nil?

        answer_callback(URI.parse("#{Forwarded.origin(target)}#{Client::FORWARD_CALLBACK}"), params[:code])
      end

      private

        def answer_callback(target, secret)
          code = ForwardCode.claim(secret)
          client = code&.client

          return head(:forbidden) if code.nil? || client.nil? || client.forward_origin != Forwarded.origin(target)
          return head(:forbidden) unless code.session&.live? && client.admits?(code.actor)

          held = ForwardSession.mint!(actor: code.actor, client: client, session: code.session,
                                      expires_at: code.session.expires_at)

          cookies[ForwardSession::COOKIE] = {
            value: held.secret, httponly: true, secure: target.scheme == "https", same_site: :lax, path: "/",
            expires: held.expires_at
          }

          redirect_to code.return_to, allow_other_host: true
        end

        def admit(actor)
          response.headers["Remote-User"] = actor.nickname.presence || actor.identifier
          response.headers["Remote-Email"] = actor.email if actor.email_verified_at.present?
          response.headers["Remote-Name"] = actor.name if actor.name.present?
          response.headers["Remote-Groups"] = actor.group_labels.join(",")

          head :ok
        end

        def return_to
          raw = request.query_string[/(?:\A|&)rd=(.*)\z/m, 1].to_s

          raw.match?(/\Ahttps?%3A/i) ? CGI.unescape(raw) : raw
        end

        def params_from(target)
          Rack::Utils.parse_query(target.query.to_s)
        end
    end
  end
end
