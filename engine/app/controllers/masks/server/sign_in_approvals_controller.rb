module Masks
  module Server
    class SignInApprovalsController < ApplicationController
      HELD = "approving".freeze

      before_action :require_trusted_device

      rate_limit to: ::Rails.configuration.masks.account_attempt_limit,
                 within: 3.minutes,
                 only: :create,
                 by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
                 with: -> { refuse(t("sign_in_approvals.too_many_attempts")) }

      def create
        approval = SignInApproval.matching(actor: current_actor, code: params[:code], from: current_device)

        return refuse(t("sign_in_approvals.no_match")) if approval.nil?

        session[HELD] = approval.id

        redirect_to root_path(anchor: "approve")
      end

      def update
        approval = SignInApproval.waiting.find_by(id: session.delete(HELD), actor_id: current_actor.id)
        verdict = params[:answer] == "approve" ? "approved" : "denied"

        return refuse(t("sign_in_approvals.expired")) unless approval&.answer!(verdict, by: current_device)

        Event.record!("sign_in.#{verdict}", actor: current_actor, asking: approval.device&.label)

        redirect_to root_path, notice: t("sign_in_approvals.#{verdict}")
      end

      private

        def require_trusted_device
          return redirect_to login_path unless current_actor

          refuse(t("sign_in_approvals.untrusted")) unless DeviceFactor.satisfied?(device: current_device, actor: current_actor)
        end

        def refuse(message)
          redirect_to root_path(anchor: "approve"), alert: message
        end
    end
  end
end
