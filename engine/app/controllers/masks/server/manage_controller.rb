module Masks
  module Server
    class ManageController < ApplicationController
      layout "masks/server/manage"

      def index
        @boot = {
          issuer: issuer.url,
          resource: issuer.manage_resource,
          graphql: manage_graphql_path,
          root: manage_path,
          clientId: Client.console!(issuer).client_id,
          account: root_path,
          tenant: current_tenant.to_identity,
          copy: I18n.t("manage", default: {})
        }
      end
    end
  end
end
