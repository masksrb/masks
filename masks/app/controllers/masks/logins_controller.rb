# frozen_string_literal: true

module Masks
  # Login endpoint.
  #
  # Handles GET, POST and DELETE, eventually redirecting back
  # to the given redirect_uri with a valid token once logged in.
  class LoginsController < ApplicationController
    include Masks::Controller

    policy as: :controller do
      inherit :login
    end

    # helper_method :login_json

    # def show
      # render_login
    # end

    # def update
    # end

    # private

    # def login
      # @login ||= Masks.login(request)
    # end

    # def render_login
      # respond_to do |format|
        # format.html { render :show }
        # format.json { render json: login_json }
      # end
    # end

    # def login_data
      # {}
    # end

    # def login_json
      # @login_json ||=
        # begin
          # if Masks.mode.debug
            # JSON.pretty_generate(login_data)
          # else
            # login_data.to_json
          # end
        # end
    # end

  end
end


# frozen_string_literal: true

# module Masks
  # module FrontendController
    # extend ActiveSupport::Concern

    # class_methods do
      # def masks_layout
        # layout :masks_layout
      # end
    # end

    # included do
      # helper_method :frontend_props
      # helper_method :frontend_json
    # end

    # private

    # def masks_device
      # request.env[Masks.devices.env_key]
    # end

    # def frontend_props(**updates)
      # @frontend_props ||= default_props
      # @frontend_props.deep_merge!(updates) if updates.keys.any?
      # @frontend_props
    # end

    # def frontend_hash
      # frontend_props.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    # end

    # def frontend_json
      # frontend_hash.to_json
    # end

    # def render_masks(status:)
      # respond_to do |format|
        # format.html { render masks_view, status: }
        # format.json { render json: masks_json, status: }
      # end
    # end

    # def masks_layout
      # Masks.conf.theme_layout
    # end

    # def masks_view
      # Masks.conf.theme_login
    # end

    # def masks_json
      # frontend_hash
    # end

    # def default_props
      # { version: Masks::VERSION.to_s, favicon: Masks.mode.favicon_url }
    # end
  # end
# end
