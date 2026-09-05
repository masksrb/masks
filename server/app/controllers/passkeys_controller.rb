class PasskeysController < ApplicationController
  HELD = "passkey_registration".freeze

  before_action :require_actor

  def create
    held = session.delete(HELD)

    return refuse("That enrolment expired. Try again.") if held.blank?
    return refuse("You already have as many passkeys as this server keeps.") if crowded?

    credential = RelyingParty.for.verify_registration(attestation, held)

    Passkey.enrol!(actor: current_actor, credential: credential, name: params[:name])

    redirect_to root_path, notice: "Passkey added."
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid, JSON::ParserError
    refuse("That passkey could not be added.")
  end

  def challenge
    held = RelyingParty.for.registration_options(current_actor)

    session[HELD] = held.challenge

    render json: held.as_json
  end

  def destroy
    passkey = Passkey.find_by(id: params[:id], actor_id: current_actor.id)

    return refuse("There is no such passkey on this account.") if passkey.nil?

    passkey.destroy!

    redirect_to root_path, notice: "Passkey removed."
  end

  private

    def require_actor
      redirect_to login_path unless current_actor
    end

    def crowded?
      Passkey.where(actor_id: current_actor.id).count >= Passkey::MAX_PER_ACTOR
    end

    def attestation
      JSON.parse(params.require(:credential))
    end

    def refuse(message)
      redirect_to root_path, alert: message
    end
end
