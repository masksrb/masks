module Manage
  module Types
    class SignInPolicyType < BaseObject
      field :key, ID, null: false
      field :name, String, null: false
      field :signup, Boolean, null: false
      field :nickname, String, null: false
      field :email, String, null: false
      field :email_verified, Boolean, null: false
      field :phone, String, null: false
      field :phone_verified, Boolean, null: false
      field :password_minimum, Integer, null: false
      field :refuse_common_passwords, Boolean, null: false
      field :first_factors, [ String ], null: false
      field :second_factors, [ String ], null: false
      field :second_factor_required, Boolean, null: false
      field :email_domains, [ String ], null: false
      field :providers, [ String ]
      field :confirmation, String, null: false
      field :hidden, Boolean, null: false
      field :signup_scopes, [ String ], null: false
      field :clients, [ "Manage::Types::ClientType" ], null: false
      field :default, Boolean, null: false
      field :archived_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      def signup_scopes
        object.signup_scope_list
      end

      def clients
        object.clients.reject(&:archived?).sort_by(&:name)
      end

      def default
        Current.tenant.sign_in_policy_id == object.id
      end
    end
  end
end
