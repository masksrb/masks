class GraphQLTestCase < AuthTestCase
  def gql(query, **vars)
    raw_gql(query, **vars)
    assert_not gql_errors
  end

  def raw_gql(query, **vars)
    post "/login.graphql", as: :json, params: { query:, variables: vars }
  end

  def gql_result(*keys)
    response.parsed_body.dig(*["data", *keys])
  end

  def gql_errors
    response.parsed_body.dig("errors")
  end

  def client
    @client ||= manage_client
  end

  def entry_params
    {}
  end

  def self.managers_only(name, query, **vars, &block)
    setup do
      traditional_login!

      log_in "manager"
    end

    test "masks:manage is required for #{name}" do
      vars = self.instance_exec(&block) if block_given?

      raw_gql query, **vars

      manager.scopes = ""
      manager.save!

      raw_gql query, **vars

      assert gql_errors
      assert_not gql_result
    end
  end

  def self.paginated(key, query, &block)
    test "#{key} can be paginated" do
      (Masks::MasksSchema::PAGE_SIZE + 1).times { instance_exec(&block) }

      gql query

      assert gql_result.dig(key, "pageInfo", "hasNextPage")
      assert_equal Masks::MasksSchema::PAGE_SIZE,
                   gql_result.dig(key, "nodes").length
    end
  end
end
