module Masks
  class ManageController < ManagersController
    layout "masks/application"

    def index
      assign_masks
      # frontend_props(
      #   device: {
      #     id: current_device.public_id,
      #   },
      #   actor:
      #     current_manager.slice(:identifier, :identicon_id, :avatar_url).merge(
      #       id: current_manager.key,
      #     ),
      # )

      render "masks/manage"
    end

    def assign_masks
      super.merge!(
        url: params[:url] || "",
        root: main_app.masks_manage_path,
        graphql: main_app.masks_graphql_path,
        profile: masks_profile_url,
        actor: current_actor.public_json,
        device: {
          id: current_device.public_id,
        },
      )
    end
  end
end
