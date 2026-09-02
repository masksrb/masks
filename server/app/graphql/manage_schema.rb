class ManageSchema < GraphQL::Schema
  query Manage::Types::QueryType
  mutation Manage::Types::MutationType

  max_depth 12
  max_complexity 300
  max_query_string_tokens 5000
  validate_max_errors 100

  def self.unauthorized_object(error)
    raise GraphQL::ExecutionError, "#{error.type.graphql_name} is not accessible"
  end

  def self.type_error(error, context)
    raise GraphQL::ExecutionError, error.message
  end
end
