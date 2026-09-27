module Masks
  module Server
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
          argument :apps_require_second_factor, Boolean, required: false
          argument :refuse_breached_passwords, Boolean, required: false,
                                                    description: "Checks new passwords, and each one used to sign in, against known breaches without sending the password."
          argument :risk_step_up_at, Integer, required: false, description: "A risk score, 1 to 100, from which a sign-in is asked for a second factor. Null never asks."
          argument :risk_refuse_at, Integer, required: false, description: "A risk score, 1 to 100, from which a sign-in is refused. Null never refuses."
          argument :session_lifetime, Integer, required: false,
                                               description: "Seconds a session lasts after signing in. Null keeps the 14-day default."
          argument :session_idle_timeout, Integer, required: false,
                                                   description: "Seconds of inactivity that end a session. Null never ends one for being idle."
          argument :email_domains, [ String ], required: false
          argument :providers, [ String ], required: false
          argument :every_provider, Boolean, required: false
          argument :confirmation, String, required: false
          argument :hidden, Boolean, required: false
          argument :signup_scopes, [ String ], required: false

          field :sign_in_policy, Types::SignInPolicyType, null: false

          private

            NULLABLE = %i[session_lifetime session_idle_timeout risk_step_up_at risk_refuse_at].freeze

            def apply(policy, signup_scopes: nil, every_provider: nil, providers: nil, **attributes)
              policy.assign_attributes(attributes.slice(*NULLABLE))
              policy.assign_attributes(attributes.except(*NULLABLE).compact)
              policy.signup_scopes = Scopes.join(signup_scopes).presence unless signup_scopes.nil?
              policy.providers = providers unless providers.nil?
              policy.providers = nil if every_provider

              policy
            end
        end
      end
    end
  end
end
