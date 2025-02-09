module Masks
  module Seedable
    extend ActiveSupport::Concern

    included do
      attribute :local

      validate :validate_local

      scope :with_locals, -> { [*local_records, *to_a] }
    end

    class_methods do
      def yml_file
        @yml_file ||= "#{name.split("::").last.tableize}"
      end

      def yml_data
        Masks::Shims::YML.layer(yml_file)
      end

      def local_records
        yml_data
          .map { |key, attrs| seed(key:, **attrs) if attrs[:local] }
          .compact
      end

      def seed_data
        yml_data
          .map { |key, attrs| [key, attrs] unless attrs[:local] }
          .compact
          .to_h
          .deep_symbolize_keys
      end

      def seed(**attrs)
        new(**attrs)
      end

      def seed!(**attrs)
        record = seed(**attrs)
        return unless record
        record.save

        type_name = record.class.name.split("::").last.humanize

        if record.valid?
          Masks.logger.info("#{type_name} '#{record.key}' seeded")
        elsif !record.local
          Masks.logger.warn(
            "#{type_name} '#{record.key}' invalid: #{record.errors.full_messages.first}",
          )
        end

        record
      end

      def seed_all
        seed_data.map { |key, yml| seed!(key:, **yml) }
      end
    end

    def validate_local
      errors.add(:base, :local) if local
    end
  end
end
