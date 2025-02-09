module Masks
  module Controller
    extend ActiveSupport::Concern

    class_methods do
      def masks_layout
        layout :theme_layout
      end

      def managers_only(**opts)
        internal_endpoint managers_only: true, **opts
      end

      def internal_endpoint(*args, **opts, &block)
        use Masks::InternalEndpoint, *args, **opts, &block
      end
    end

    included do
      delegate :theme_layout, :theme_view, to: :masks_conf

      helper_method :masks_login_json
      helper_method :masks_styles
      helper_method :masks_client

      alias_method :masks_client, :current_client
    end

    def masks_session
      Masks::Session.env(request.env)
    end

    def masks_conf
      Masks.conf
    end

    def masks_login
      @masks_login ||=
        request.env["masks.login"]&.sort_by { |k, _| k.to_s }&.to_h
    end

    def masks_profile_url
      if current_actor && current_client
        main_app.masks_login_path(
          current_client,
          prompt: "profile",
          login_hint: current_actor.identifier,
          redirect_uri: request.path,
        )
      end
    end

    def masks_json
      @masks.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    end

    def masks_styles
      return "" unless current_client

      current_client.styles
    end

    def masks_login_json
      @masks_login_json ||=
        begin
          if Masks.conf.debug
            JSON.pretty_generate(masks_json)
          else
            masks_json.to_json
          end
        end
    end

    def assign_masks
      @masks ||=
        begin
          login = masks_login ? masks_login : nil

          value = {
            version: Masks::VERSION.to_s,
            favicon: Masks.conf.favicon_url,
            login:,
          }.compact

          value
        end
    end

    def render_masks(prompt: nil)
      assign_masks

      @masks[:login]["prompt"] = prompt if prompt && @masks[:login]

      respond_to do |format|
        format.html { render theme_view, status: }
        format.json { render json: masks_json["login"], status: }
      end
    end

    delegate :current_device,
             :current_client,
             :current_actor,
             to: :masks_session
  end
end
