module Masks
  module Server
    module Manage
      module Mutations
        class RestoreSignInPolicy < BaseMutation
          argument :key, ID

          field :sign_in_policy, Types::SignInPolicyType, null: false

          def resolve(key:)
            policy = sign_in_policy!(key)

            refuse!("#{policy.name} is not archived") unless policy.archived?

            policy.archived_at = nil
            save!(policy)

            audit!(Masks::Server::Event::SIGN_IN_POLICY_UPDATED, policy: policy.key, name: policy.name, changed: [ "restored" ])

            { sign_in_policy: policy }
          end
        end
      end
    end
  end
end
