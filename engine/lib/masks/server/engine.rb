module Masks
  module Server
    class Engine < ::Rails::Engine
      isolate_namespace Masks::Server

      initializer "masks_server.migrations" do |app|
        unless app.root.to_s == root.to_s
          config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
        end
      end
    end
  end
end
