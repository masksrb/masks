module Masks
  class Loader
    class << self
      def file(name)
        paths(name).reverse.each do |path|
          return File.open(path) if path.exist?
        end
      end

      def yml(file)
        result = {}

        paths("#{file.to_s.delete_suffix(".yml")}.yml").each do |path|
          if path.exist?
            data = ActiveSupport::ConfigurationFile.parse(path)
            result.deep_merge!(
              (data&.fetch(Masks.env, data) || {}).deep_symbolize_keys,
            )
          end
        end

        result
      end

      def paths(path)
        result = [Masks::SRC.join("config").join(path)]

        if defined?(Rails) && Rails.root
          result << Rails.root.join("config").join(path)
        end

        result << Masks.conf_dir.join(path) if Masks.conf_dir

        result
      end
    end
  end
end
