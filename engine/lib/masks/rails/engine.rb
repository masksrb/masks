module Masks
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace Masks::Rails

      config.masks = Masks::Rails.config

      # Opt-in, not blanket. This used to `include Masks::Rails::Authentication`
      # into every controller in the host app, which lands twenty-five `masks_*`
      # methods and four helper_methods on code the consumer owns, with no way
      # to say no — and a name collision found that way is the kind of thing
      # `grants:` versus `scope:` already cost this project once.
      initializer "masks.authentication" do
        ActiveSupport.on_load(:action_controller) do
          include Masks::Rails::Authentication if Masks::Rails.config.authenticate_everything
        end
      end
    end
  end
end
