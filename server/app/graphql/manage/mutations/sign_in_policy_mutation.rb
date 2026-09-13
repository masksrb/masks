module Manage
  module Mutations
    class SignInPolicyMutation < BaseMutation
      argument :name, String, required: false
      argument :signup, Boolean, required: false
      argument :nickname, String, required: false
      argument :email, String, required: false
      argument :email_verified, Boolean, required: false
      argument :phone, String, required: false
      argument :phone_verified, Boolean, required: false
      argument :password_minimum, Integer, required: false
      argument :refuse_common_passwords, Boolean, required: false
      argument :first_factors, [ String ], required: false
      argument :second_factors, [ String ], required: false
      argument :second_factor_required, Boolean, required: false
      argument :email_domains, [ String ], required: false
      argument :providers, [ String ], required: false
      argument :every_provider, Boolean, required: false
      argument :confirmation, String, required: false
      argument :hidden, Boolean, required: false
      argument :signup_scopes, [ String ], required: false

      field :sign_in_policy, Types::SignInPolicyType, null: false

      private

        def apply(policy, signup_scopes: nil, every_provider: nil, providers: nil, **attributes)
          policy.assign_attributes(attributes.compact)
          policy.signup_scopes = Scopes.join(signup_scopes).presence unless signup_scopes.nil?
          policy.providers = providers unless providers.nil?
          policy.providers = nil if every_provider

          policy
        end
    end
  end
end
