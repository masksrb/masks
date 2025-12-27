module Masks
  class LoginPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    def default_policies
      device
      client
    end

    checks :request do |policy|
      case request.method
      when 'GET'
        render 'masks/login_policy/new'
      when 'POST'
        # TODO: Implement authentication logic
        render 'masks/login_policy/new', status: :unprocessable_entity
      end
    end
  end
end
