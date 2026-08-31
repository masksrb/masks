module Masks
  module Rails
    def self.parent_controller
      config.parent_controller.to_s.constantize
    end

    class BaseController < parent_controller
      include Masks::Rails::Authentication

      layout "masks/rails/plain"
    end
  end
end
