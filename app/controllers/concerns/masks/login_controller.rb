module Masks
  module LoginController
    extend ActiveSupport::Concern

    class_methods do
      def masks_layout
        layout :masks_layout
      end
    end

    included do
      include Masks::ProtectedController

      helper_method :login_json
    end

    def masks_login
      @masks_login ||=
        request.env["masks.login"]&.sort_by { |k, _| k.to_s }&.to_h
    end

    def masks_json
      @masks.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    end

    def login_json
      @login_json ||=
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

          value = { login: }.compact

          value
        end
    end

    def render_login(prompt: nil)
      assign_masks

      @masks[:login]["prompt"] = prompt if prompt && @masks[:login]

      respond_to do |format|
        format.html { render masks_view, status: }
        format.json { render json: masks_json["login"], status: }
      end
    end

    def masks_layout
      Masks.conf.theme_layout
    end

    def masks_view
      Masks.conf.theme_view
    end
  end
end
