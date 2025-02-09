module Masks
  class ManageController < ManagersController
    def index
      frontend_props(
        theme: "luxury",
        section: "Manage",
        url: params[:url] || "",
        install: masks_install.public_settings,
        device: {
          id: current_device.public_id,
        },
        actor:
          current_manager.slice(:identifier, :identicon_id, :avatar_url).merge(
            id: current_manager.key,
          ),
      )

      render "manage"
    end
  end
end
