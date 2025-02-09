# frozen_string_literal: true

module Masks::Types
  class BaseObject < GraphQL::Schema::Object
    edge_type_class(BaseEdge)
    connection_type_class(BaseConnection)
    field_class BaseField

    class << self
      def bool(name, null: true, prefix: nil)
        method = prefix ? "#{prefix}_#{name}" : name

        field(method, GraphQL::Types::Boolean, null: null)

        define_method method do
          object.send("#{name}?")
        end
      end
    end
  end
end
