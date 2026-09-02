module Manage
  module Types
    class ActorType < BaseObject
      field :uuid, ID, null: false
      field :nickname, String, null: false
      field :email, String
      field :email_verified, Boolean, null: false
      field :scopes, [ String ], null: false
      field :otp_enabled, Boolean, null: false
      field :backup_codes_remaining, Integer, null: false
      field :backup_codes_generated_at, GraphQL::Types::ISO8601DateTime
      field :last_login_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :name, String
      field :given_name, String
      field :family_name, String
      field :middle_name, String
      field :profile_url, String
      field :picture_url, String
      field :website_url, String
      field :gender, String
      field :birthdate, String
      field :zoneinfo, String
      field :locale, String

      def email_verified
        object.email_verified_at.present?
      end

      def scopes
        object.scope_list
      end

      def otp_enabled
        object.otp?
      end
    end
  end
end
