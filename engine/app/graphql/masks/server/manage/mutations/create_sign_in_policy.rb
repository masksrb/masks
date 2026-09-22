module Masks
  module Server
    module Manage
      module Mutations
        class CreateSignInPolicy < SignInPolicyMutation
          argument :key, ID

          def resolve(key:, name: nil, **attributes)
            refuse!("a sign-in policy is already keyed #{key}") if Masks::Server::SignInPolicy.exists?(key: key)

            policy = apply(Masks::Server::SignInPolicy.new(key: key, name: name), **attributes)

            save!(policy)
            audit!(Masks::Server::Event::SIGN_IN_POLICY_CREATED, policy: policy.key, name: policy.name)

            { sign_in_policy: policy }
          end
        end
      end
    end
  end
end
