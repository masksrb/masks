module Manage
  module Types
    class UploadType < GraphQL::Schema::Scalar
      graphql_name "Upload"

      def self.coerce_input(value, _context)
        return value if value.respond_to?(:read)

        raise GraphQL::CoercionError, "that argument has to be an uploaded file"
      end

      def self.coerce_result(_value, _context)
        raise GraphQL::CoercionError, "an upload is never handed back"
      end
    end
  end
end
