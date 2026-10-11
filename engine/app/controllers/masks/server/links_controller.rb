module Masks
  module Server
    class LinksController < ApplicationController
      def invitation
        hand_over(Invitation, LoginStates::Invitation::HELD, "invitation")
      end

      def reset
        hand_over(PasswordReset, LoginStates::PasswordReset::HELD, "reset")
      end

      def verify
        @actor = EmailVerification.settle!(params[:token])

        if @actor.nil?
          @kind = "confirmation"
          return render :expired, status: :gone
        end

        Event.record!(Event::EMAIL_VERIFIED, actor: @actor, email: @actor.email)

        render :verified
      end

      private

        def hand_over(token, slot, kind)
          if token.redeem(params[:token]).nil?
            @kind = kind
            return render :expired, status: :gone
          end

          sign_out if current_actor

          replace_login(slot => params[:token])

          redirect_to login_path
        end
    end
  end
end
