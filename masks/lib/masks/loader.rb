# frozen_string_literal: true

module Masks
  class Loader
    class << self
      def file(name)
        paths(name).reverse_each do |path|
          return File.open(path) if path.exist?
        end
      end

      def yml(file = 'masks.yml')
        result = {}

        paths("#{file.to_s.delete_suffix('.yml')}.yml").each do |path|
          next unless path.exist?

          data = ActiveSupport::ConfigurationFile.parse(path)
          result.deep_merge!(
            (data&.fetch(Masks.env, data) || {}).deep_symbolize_keys
          )
        end

        result
      end

      def paths(path)
        result = [Masks::SRC.join('config').join(path)]
        result << Rails.root.join('config').join(path) if defined?(Rails) && Rails.root
        result << Masks.conf_dir.join(path) if Masks.conf_dir
        result
      end
    end
  end
end
