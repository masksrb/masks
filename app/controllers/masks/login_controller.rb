module Masks
  class LoginController < ApplicationController
    use Masks::LoginEndpoint

    include Masks::Controller

    masks_layout

    def endpoint
      render_masks
    end
  end
end
