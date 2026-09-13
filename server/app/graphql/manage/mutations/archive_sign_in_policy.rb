module Manage
  module Mutations
    class ArchiveSignInPolicy < BaseMutation
      argument :key, ID

      field :sign_in_policy, Types::SignInPolicyType, null: false

      def resolve(key:)
        policy = sign_in_policy!(key)

        refuse!("#{policy.name} is already archived") if policy.archived?
        refuse!("#{policy.name} is the tenant's default; choose another default first") if
          Current.tenant.sign_in_policy_id == policy.id

        policy.archived_at = Time.current
        save!(policy)

        audit!(::Event::SIGN_IN_POLICY_ARCHIVED, policy: policy.key, name: policy.name,
                                                 clients: policy.clients.count)

        { sign_in_policy: policy }
      end
    end
  end
end
