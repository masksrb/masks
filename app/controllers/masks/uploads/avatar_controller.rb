module Masks
  module Uploads
    class AvatarController < ManagersController
      def create
        actor = Masks.actors.identify(key: params[:actor_id], required: true)

        render json: {}, status: 404 unless actor

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
