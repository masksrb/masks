module Masks
  class OidcPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    def default_policies
      device
      client
    end

    checks :request do |policy|
      # TODO: Implement OIDC logic
      render plain: 'OIDC not implemented', status: :not_implemented
    end
  end
end
