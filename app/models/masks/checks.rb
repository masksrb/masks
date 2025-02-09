module Masks
  module Checks
    class << self
      def names(value)
        result = value.present? ? value.map { |v| to_name(v) } : []
        result.compact
      end

      def to_name(name)
        return unless name.present?

        name = name.to_s
        name =
          (
            if name.include?("::")
              name
            else
              "Masks::Checks::#{name.underscore.camelize}"
            end
          )
        name.constantize.to_s
      end

      def to_cls(name)
        to_name(name).constantize
      end
    end
  end
end
