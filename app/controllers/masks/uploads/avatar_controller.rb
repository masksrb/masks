module Masks
  module Uploads
    class AvatarController < ManagersController
      def create
        actor = Masks::Actor.find_by!(key: params[:actor_id])
        actor.avatar.attach(params[:file])

        render json: {
                 url:
                   rails_storage_proxy_url(
                     actor.avatar,
                     **Masks.default_url_options,
                   ),
               }
      end
    end
  end
end
