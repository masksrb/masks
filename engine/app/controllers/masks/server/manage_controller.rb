module Masks
  module Server
    class ManageController < ApplicationController
      layout "masks/server/manage"

      def index
        @boot = {
          issuer: issuer.url,
          resource: issuer.manage_resource,
          graphql: manage_graphql_path,
          root: "/manage",
          tenant: current_tenant.to_identity
        }
      end
    end
  end
end
