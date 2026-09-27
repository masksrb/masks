module Masks
  module Server
    class OrganizationMembersController < ApplicationController
      ANCHOR = "organizations".freeze

      class NotOwner < StandardError; end

      rescue_from NotOwner do
        back(alert: t("organization_members.owners_only", organization: @organization.name))
      end

      rate_limit to: 30, within: 1.minute, only: :create,
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

      def accept
        @own.accept!

        back(notice: t("organization_members.accepted", organization: @organization.name, role: @own.role))
      rescue Membership::Unconfirmed
        back(alert: t(current_actor.email.to_s.casecmp?(@own.invited_as.to_s) ? "organization_members.confirm_first" : "organization_members.elsewhere",
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
          redirect_to root_path(anchor: ANCHOR), **flash
        end
    end
  end
end
