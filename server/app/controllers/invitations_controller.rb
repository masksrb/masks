class InvitationsController < ApplicationController
  def show
    invitation = Invitation.redeem(params[:token])

    return render :expired, status: :gone if invitation.nil?

    sign_out if current_actor

    session[LoginsController::STORE] = { LoginStates::Invitation::HELD => params[:token] }

    redirect_to login_path
  end
end
