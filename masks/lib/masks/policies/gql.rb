module Masks
  class GqlPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    def default_policies
      device
      client
    end

    checks :request do |policy|
      # TODO: Implement GraphQL endpoint logic
      render plain: 'GraphQL not implemented', status: :not_implemented
    end
  end
end
