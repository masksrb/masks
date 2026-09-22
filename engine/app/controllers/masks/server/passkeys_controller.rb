module Masks
  module Server
    class PasskeysController < ApplicationController
      HELD = "passkey_registration".freeze

      before_action :require_actor

      def create
        held = session.delete(HELD)

        return refuse(t("passkeys.expired")) if held.blank?
        return refuse(t("passkeys.crowded")) if Passkey.crowded?(current_actor)

        credential = RelyingParty.for.verify_registration(attestation, held)

        Passkey.register!(actor: current_actor, credential: credential, name: params[:name])

        redirect_to root_path, notice: t("passkeys.added")
      rescue WebAuthn::Error, ActiveRecord::RecordInvalid, JSON::ParserError
        refuse(t("passkeys.unusable"))
      end

      def challenge
        held = RelyingParty.for.registration_options(current_actor)

        session[HELD] = held.challenge

        render json: held.as_json
      end

      def destroy
        passkey = Passkey.find_by(id: params[:id], actor_id: current_actor.id)

        return refuse(t("passkeys.unknown")) if passkey.nil?
        return refuse(t("passkeys.last_way_in")) if current_actor.last_way_in?(passkey)

        passkey.destroy!

        Event.record!(Event::PASSKEY_REMOVED, actor: current_actor, passkey: passkey.name)

        redirect_to root_path, notice: t("passkeys.removed")
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end


        def attestation
          JSON.parse(params.require(:credential))
        end

        def refuse(message)
          redirect_to root_path, alert: message
        end
    end
  end
end
