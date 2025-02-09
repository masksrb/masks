# frozen_string_literal: true

module Masks::Types
  class CamelizedJSON < GraphQL::Types::JSON
    def self.coerce_input(value, _context)
      case value
      when Hash
        value.deep_transform_keys { |k| k.to_s.underscore }
      else
        value
      end
    end

    def self.coerce_result(value, _context)
      case value
      when Hash
        value.deep_transform_keys { |k| k.to_s.camelize(:lower) }
      else
        value
      end
    end
  end
end
