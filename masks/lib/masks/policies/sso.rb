module Masks
  class SsoPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    def default_policies
      device
      client
    end

    checks :request do |policy|
      # TODO: Implement SSO logic
      render plain: 'SSO not implemented', status: :not_implemented
    end
  end
end
