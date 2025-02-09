module Masks
  class ClientsController < ActionController::Base
    def css
      client = Masks.client(params[:client_id]) if params[:client_id] !=
        ".defaults"
      styles =
        if client && File.exist?(Masks.dir.join("styles", "#{client.key}.css"))
          File.read(Masks.dir.join("styles", "#{client.key}.css"))
        elsif File.exist?(Masks.dir.join("clients.css"))
          File.read(Masks.dir.join("clients.css"))
        else
          File.read(Masks::Engine.root.join("config/clients.css"))
        end

      render body: styles, content_type: "text/css"
    end
  end
end
