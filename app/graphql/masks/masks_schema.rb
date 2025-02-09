# frozen_string_literal: true

module Masks
  class MasksSchema < GraphQL::Schema
    PAGE_SIZE = 25

    class << self
      def manager?(context)
        Entries::Internal.manager?(context[:session])
      end
    end

    # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
    use GraphQL::Dataloader
    use GraphQL::Schema::Visibility

    mutation(Types::MutationType)
    query(Types::QueryType)

    orphan_types Types::ClientType

    # GraphQL-Ruby calls this when something goes wrong while running a query:
    def self.type_error(err, context)
      # if err.is_a?(GraphQL::InvalidNullError)
      #   # report to your bug tracker here
      #   return nil
      # end
      super
    end

    # Union and Interface Resolution
    def self.resolve_type(abstract_type, obj, ctx)
      case obj
      when Client
        Types::ClientType
      else
        raise(GraphQL::RequiredImplementationMissingError)
      end
    end

    # Limit the size of incoming queries:
    max_query_string_tokens(5000)

    # Stop validating when it encounters this many errors:
    validate_max_errors(100)

    # Pagination
    default_max_page_size PAGE_SIZE
  end
end
