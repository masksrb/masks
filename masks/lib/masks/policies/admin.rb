module Masks
  class AdminPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    def default_policies
      device
      client
    end

    checks :request do |policy|
      # TODO: Implement admin panel logic
      render plain: 'Admin not implemented', status: :not_implemented
    end
  end
end
