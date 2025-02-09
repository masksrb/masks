module Masks
  class ManageController < ManagersController
    layout "masks/application"

    def index
      frontend_props(
        url: params[:url] || "",
        root: main_app.masks_manage_path,
        graphql: main_app.masks_graphql_path,
        profile: masks_profile_url,
        actor: current_actor.public_json,
        device: current_device.public_json,
      )

      render "masks/manage"
    end
  end
end
