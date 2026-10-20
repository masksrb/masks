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
        return basic(client, target) if ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

        held = ForwardSession.held(cookies[ForwardSession::COOKIE], client)
        decided = client.forward_rules.decide(path: target.path, method: forwarded_method, address: request.remote_ip,
                                              actor: held&.actor)

        case decided.outcome
        when ForwardAuthRules::OPEN then admit(held&.actor)
        when ForwardAuthRules::DENY then head(:forbidden)
        when ForwardAuthRules::ONE_FACTOR then held ? admit(held.actor) : ask_to_sign_in(target)
        when ForwardAuthRules::TWO_FACTOR then held&.session&.multi_factored? ? admit(held.actor) : ask_to_sign_in(target)
        else
          complete = held if held&.session&.complete?
          decided.outcome == ForwardAuthRules::TOKEN ? admit_presented(client, complete) : answer(complete, target)
        end
      end

      def start
        target = URI.parse(return_to)
        client = Client.forwarding_to(target)

        return render(plain: t("forward_auth.unknown"), status: :not_found) if client.nil?

        decided = client.forward_rules.decide(path: target.path, method: "GET", address: request.remote_ip, actor: current_actor)

        return render(plain: t("forward_auth.denied", app: client.name), status: :forbidden) if decided.outcome == ForwardAuthRules::DENY
        return send_to_login(decided) if current_actor.nil?

        unless client.admits?(current_actor)
          return redirect_to(target.to_s, allow_other_host: true) if decided.outcome == ForwardAuthRules::OPEN

          return render(plain: t("forward_auth.not_admitted", app: client.name), status: :forbidden)
        end

        return step_up if decided.outcome == ForwardAuthRules::TWO_FACTOR && !current_session.multi_factored?
        return step_up if [ ForwardAuthRules::ONE_FACTOR, ForwardAuthRules::OPEN ].exclude?(decided.outcome) && !current_session.complete?

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

        def basic(client, target)
          identifier, secret = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
          outcome = AppPasswords.authenticate(client: client, identifier: identifier, secret: secret, via: "forward_auth")

          return head(:too_many_requests) if outcome.throttled?
          return head(:unauthorized) if outcome.actor.nil?

          decided = client.forward_rules.decide(path: target.path, method: forwarded_method, address: request.remote_ip,
                                                actor: outcome.actor)
          return head(:forbidden) if decided.outcome == ForwardAuthRules::DENY

          admit(outcome.actor)
        end

        def answer(held, target)
          held ? admit(held.actor) : ask_to_sign_in(target)
        end

        def ask_to_sign_in(target)
          return head(:unauthorized) if params[:status] == "401"

          redirect_to forward_auth_start_url(rd: target.to_s), allow_other_host: true
        end

        def send_to_login(decided)
          Login.new(store: login_store).relax! if decided.outcome == ForwardAuthRules::ONE_FACTOR

          redirect_to login_path(return_to: request.fullpath)
        end

        def step_up
          Login.new(store: login_store).step_up!

          redirect_to login_path(return_to: request.fullpath)
        end

        def admit_presented(client, held)
          return admit(held.actor) if held

          token = presented_token(client)
          return admit(token.actor, machine: token.client) if token

          response.headers["WWW-Authenticate"] = %(Bearer realm="#{client.forward_origin}")
          head :unauthorized
        end

        def presented_token(client)
          scheme, secret = request.authorization.to_s.split(" ", 2)
          return nil unless scheme.to_s.casecmp?("Bearer") && secret.present?

          claims = AccessToken.decode(secret.strip, issuer: issuer)
          token = AccessToken.live.includes(:actor, :client).find_by(digest: claims["jti"])

          return nil if token.nil? || token.bound? || token.client.nil?
          return nil unless token.client_id == client.id || Array(token.audience).include?(client.forward_origin)
          return nil if token.actor && (token.actor.suspended? || !client.admits?(token.actor))

          token
        rescue JWT::DecodeError
          nil
        end

        def admit(actor, machine: nil)
          if actor
            response.headers["Remote-User"] = actor.nickname.presence || actor.identifier
            response.headers["Remote-Email"] = actor.email if actor.email_verified_at.present?
            response.headers["Remote-Name"] = actor.name if actor.name.present?
            response.headers["Remote-Groups"] = actor.group_labels.join(",")
          elsif machine
            response.headers["Remote-User"] = machine.client_id
            response.headers["Remote-Name"] = machine.name
            response.headers["Remote-Groups"] = ""
          end

          head :ok
        end

        def forwarded_method
          request.headers["X-Forwarded-Method"].presence || request.headers["X-Original-Method"].presence || "GET"
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
