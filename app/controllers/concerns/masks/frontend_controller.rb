module Masks
  module FrontendController
    extend ActiveSupport::Concern

    included do
      helper_method :frontend_props
      helper_method :frontend_json
    end

    private

    def render_error(status:, prompt: "error", **opts)
      frontend_props(
        backend: { settings: Masks.conf.public_settings, prompt: }.merge(opts),
      )

      render "app", status:
    end

    def render_404
      render_error status: 404, error: "Not found"
    end

    def default_props
      props = { version: Masks::VERSION.to_s }

      props.merge(favicon: Masks.conf.favicon_url)
    end

    def frontend_props(**updates)
      @frontend_props ||= default_props
      @frontend_props.deep_merge!(updates) if updates.keys.any?
      @frontend_props
    end

    def frontend_json
      frontend_props
        .deep_transform_keys do |key|
          key.to_s == "__typename" ? key : key.to_s.camelize(:lower)
        end
        .to_json
    end
  end
end
