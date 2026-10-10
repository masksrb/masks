module Masks
  module Server
    class ProfilesController < ApplicationController
      before_action :require_actor

      def update
        return refuse(t("profiles.directed")) if current_actor.directed?

        current_actor.assign_attributes(profile)
        changed = current_actor.changed

        return refuse(t("profiles.invalid", errors: current_actor.errors.full_messages.to_sentence)) unless current_actor.save

        Event.record!(Event::ACTOR_UPDATED, actor: current_actor, changed: changed) if changed.any?

        redirect_to root_path(anchor: "profile"), notice: t("profiles.updated")
      end

      private

        def profile
          params.permit(:name, :nickname).to_h.transform_values { |value| value.strip.presence }
        end

        def require_actor
          redirect_to login_path unless current_actor
        end

        def refuse(message)
          redirect_to root_path(anchor: "profile"), alert: message
        end
    end
  end
end
