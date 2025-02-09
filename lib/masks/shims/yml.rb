module Masks
  module Shims
    class YML
      class << self
        def layer(name)
          defaults = import(name, root: Masks::Engine.root.join("config"))
          rails = import(name, root: Rails.root.join("config"))
          customs = import(name, root: Pathname.new(ENV["MASKS_DIR"])) if ENV[
            "MASKS_DIR"
          ]
          defaults.deep_merge(rails).deep_merge(customs || {})
        end

        def import(name, root:)
          path = root.join("#{name}.yml")
          data = ActiveSupport::ConfigurationFile.parse(path) if path.exist?
          (data&.fetch(Rails.env.to_s, data) || {}).deep_symbolize_keys
        end
      end
    end
  end
end
