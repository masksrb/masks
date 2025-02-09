module Masks
  module Seedable
    extend ActiveSupport::Concern

    included do
      attribute :local

      validate :validate_local
    end

    class_methods do
      def yml_file
        @yml_file ||= "#{name.split("::").last.tableize}"
      end

      def yml_data
        Masks::Loader.yml(yml_file)
      end

      def local_records
        @local_records ||=
          seed_data
            .map { |key, attrs| [key, seed(**attrs)] if attrs[:local] }
            .compact
            .to_h
            .stringify_keys
      end

      def seed_data
        @seed_data ||=
          yml_data
            .map { |key, attrs| [key, { key:, **attrs }] }
            .compact
            .to_h
            .deep_symbolize_keys
      end

      def seeds_map
        @seeds_map ||=
          seed_data
            .map { |key, attrs| [key, seed(**attrs)] }
            .compact
            .to_h
            .deep_symbolize_keys
      end

      def seed(**attrs)
        raise NotImplementedError
      end
    end

    def seed
      save
    end

    def validate_local
      errors.add(:base, :local) if local
    end
  end
end
