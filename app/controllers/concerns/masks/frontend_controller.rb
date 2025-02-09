module Masks
  module FrontendController
    extend ActiveSupport::Concern

    included do
      before_action :ensure_install
      helper_method :frontend_props
      helper_method :frontend_json
      helper_method :device

      layout "masks/application"
    end

    private

    def render_error(status:, prompt: "error", **opts)
      settings = masks_install&.public_settings || {}
      frontend_props(backend: { settings:, prompt: }.merge(opts))

      render "app", status:
    end

    def render_404
      render_error status: 404, error: "Not found"
    end

    def ensure_install
      prompt = (Masks.env.debug ? "debug-install" : "error")

      render_error(status: 500, prompt:) unless masks_install
    end

    def default_props
      props = { backend: { version: Masks::VERSION.to_s } }

      return props unless masks_install

      props.merge(
        favicon: masks_install.favicon_url,
        bg_dark: @client&.bg_dark,
        bg_light: @client&.bg_light,
      )
    end

    def frontend_props(**updates)
      @frontend_props ||= {}
      @frontend_props.deep_merge!(updates) if updates.keys.any?
      @frontend_props.merge(default_props)
    end

    def frontend_json
      frontend_props
        .deep_transform_keys do |key|
          key.to_s == "__typename" ? key : key.to_s.camelize(:lower)
        end
        .to_json
    end

    def sentry
      @sentry ||= masks_install.setting(:sentry)
    end
  end
end
