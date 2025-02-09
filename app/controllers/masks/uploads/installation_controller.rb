module Masks
  module Uploads
    class InstallationController < ManagersController
      def logo
        logo =
          case params[:theme]
          when "light"
            Masks.conf.light_logo_file = params[:file]
          when "dark"
            Masks.conf.dark_logo_file = params[:file]
          end

        if logo
          render json: {
                   url:
                     rails_storage_proxy_url(logo, **Masks.default_url_options),
                 }
        else
          render json: { url: nil }
        end
      end

      def favicon
        Masks.conf.favicon_file = params[:file]

        render json: {
                 url:
                   rails_storage_proxy_url(
                     Masks.conf.favicon,
                     **Masks.default_url_options,
                   ),
               }
      end
    end
  end
end
