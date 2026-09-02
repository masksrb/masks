class LinksController < ApplicationController
  def invitation
    hand_over(Invitation, LoginStates::Invitation::HELD, "invitation")
  end

  def reset
    hand_over(PasswordReset, LoginStates::PasswordReset::HELD, "reset link")
  end

  private

    def hand_over(kind, slot, noun)
      if kind.redeem(params[:token]).nil?
        @noun = noun
        return render :expired, status: :gone
      end

      sign_out if current_actor

      session[LoginsController::STORE] = { slot => params[:token] }

      redirect_to login_path
    end
end
