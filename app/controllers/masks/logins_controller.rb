module Masks
  class LoginsController < ApplicationController
    use Masks::LoginEndpoint, only: :update

    include Masks::LoginController
    include Masks::FrontendController

    masks_layout

    def update
      render_login
    end
  end
end
