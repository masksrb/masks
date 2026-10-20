module Masks
  module Server
    class OrganizationAccessController < OrganizationMembersController
      def create
        own!

        asked = asked!
        role = params[:role].to_s

        asked.grant!(label: "#{@organization.key}:#{role}", by: current_actor, journey: Journey.account(current_actor))

        back(notice: t("organization_access.granted", identifier: asked.actor.identifier, app: asked.client.name,
                                                      role: role, organization: @organization.name))
      rescue AccessRequest::Refused => e
        back(alert: e.message)
      end

      def destroy
        own!

        asked = asked!
        asked.decline!(by: current_actor, journey: Journey.account(current_actor))

        back(notice: t("organization_access.declined", identifier: asked.actor.identifier, app: asked.client.name))
      rescue AccessRequest::Refused => e
        back(alert: e.message)
      end

      private

        def asked!
          id = params[:id].to_s[/\A\d+\z/]

          (id && AccessRequest.for_organization(@organization).includes(:actor, :client).find_by(id: id)) ||
            raise(AccessRequest::Refused, t("organization_access.unknown", organization: @organization.name))
        end
    end
  end
end
