class ManageController < ApplicationController
  layout "manage"

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
