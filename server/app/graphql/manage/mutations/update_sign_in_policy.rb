module Manage
  module Mutations
    class UpdateSignInPolicy < SignInPolicyMutation
      argument :key, ID

      def resolve(key:, **attributes)
        policy = sign_in_policy!(key)

        refuse!("#{policy.name} is archived; restore it first") if policy.archived?

        apply(policy, **attributes)

        changed = policy.changed

        save!(policy)
        audit!(::Event::SIGN_IN_POLICY_UPDATED, policy: policy.key, name: policy.name, changed: changed)

        { sign_in_policy: policy }
      end
    end
  end
end
