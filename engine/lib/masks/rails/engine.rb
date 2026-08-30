module Masks
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Masks::Rails

      config.masks = Masks::Rails.config

      initializer "masks.authentication" do
        ActiveSupport.on_load(:action_controller) do
          include Masks::Rails::Authentication
        end
      end
    end
  end
end
