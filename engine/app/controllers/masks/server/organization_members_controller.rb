module Masks
  module Server
    class OrganizationMembersController < ApplicationController
      class NotOwner < StandardError; end

      rescue_from NotOwner do
        back(alert: t("organization_members.owners_only", organization: @organization.name))
      end

      rate_limit to: 30, within: 1.minute, only: %i[create resend],
                 by: -> { [ current_tenant.id, current_actor&.id || request.remote_ip ].join(":") },
                 with: -> { back(alert: t("organization_members.slow_down")) }

      before_action :require_actor
      before_action :require_membership

      def create
        own!

        email = params[:email].to_s.strip

        Members.add!(organization: @organization, role: params[:role].to_s, by: current_actor, email: email,
                     journey: Journey.manage(current_actor))

        back(notice: t("organization_members.added", identifier: email, organization: @organization.name))
      rescue Members::Refused => e
        back(alert: e.message)
      end

      def update
        own!

        membership = member!

        Members.assign!(membership, role: params[:role].to_s, by: current_actor)

        back(notice: t("organization_members.assigned", identifier: labelled(membership), role: membership.role))
      rescue Members::Refused => e
        back(alert: e.message)
      end

      def resend
        own!

        membership = member!

        Members.resend!(membership, by: current_actor, journey: Journey.manage(current_actor))

        back(notice: t("organization_members.resent", identifier: labelled(membership),
                                                      age: helpers.distance_of_time_in_words(Membership.lifetime)))
      rescue Members::Refused => e
        back(alert: e.message)
      end

      def accept
        @own.accept!

        back(notice: t("organization_members.accepted", organization: @organization.name, role: @own.role))
      rescue Membership::Expired
        back(alert: t("organization_members.expired", organization: @organization.name))
      rescue Membership::Unconfirmed
        back(alert: t(@own.addressed_to?(current_actor) ? "organization_members.confirm_first" : "organization_members.elsewhere",
                      address: @own.invited_as, organization: @organization.name))
      end

      def destroy
        membership = member!
        leaving = membership.actor_id == current_actor.id

        own! unless leaving

        Members.remove!(membership, by: current_actor)

        if leaving
          back(notice: t(membership.pending? ? "organization_members.declined" : "organization_members.left",
                         organization: @organization.name))
        else
          back(notice: t("organization_members.removed", identifier: labelled(membership), organization: @organization.name))
        end
      rescue Members::Refused => e
        back(alert: e.message)
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end

        def require_membership
          @organization = Organization.active.find_by(key: params[:key])
          @own = @organization&.memberships&.find_by(actor: current_actor)

          back(alert: t("organization_members.unknown")) if @own.nil?
        end

        def own!
          raise NotOwner unless @own.owner?
        end

        def member!
          @organization.memberships.includes(:actor).find_by(id: params[:id].to_s) ||
            raise(Members::Refused, t("organization_members.not_a_member"))
        end

        def labelled(membership)
          Members.label(membership) || t("organization_members.invitee")
        end

        def back(**flash)
          return redirect_to(root_path(anchor: "organizations"), **flash) if @organization.nil?

          redirect_to root_path(anchor: "organization-#{@organization.key}"),
                      flash: flash.merge(organization: @organization.key)
        end
    end
  end
end
