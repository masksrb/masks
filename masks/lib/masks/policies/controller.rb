module Masks
  class ControllerPolicy
    include Policy
    include SubPolicies
    include RequestMatchers

    checks :request do |policy|
      next if path_matches?(request.path, policy.excluded)

      policy.policies.each do |p|
        next if p.config[:at] && !p.path_matches?(request.path)
        next if p.config[:method] && !p.method_matches?(request.method)
        next if p.config[:on] && !p.action_matches?(action_name)

        p.check(:request, p, context: self)
      end
    end

    def action_matches?(action)
      !config[:on] || Array(config[:on]).map(&:to_s).include?(action.to_s)
    end
  end
end
