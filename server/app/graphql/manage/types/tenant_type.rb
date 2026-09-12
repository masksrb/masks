module Manage
  module Types
    class TenantType < BaseObject
      field :uuid, ID, null: false
      field :subdomain, String, null: false
      field :name, String, null: false
      field :mails, Boolean, null: false
      field :mail_from, String
      field :smtp_address, String
      field :smtp_port, Integer
      field :smtp_username, String
      field :smtp_authentication, String
      field :smtp_domain, String
      field :smtp_tls, Boolean, null: false
      field :dynamic_registration, String, null: false
      field :dynamic_client_scopes, [ String ]
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :signing_keys, [ SigningKeyType ], null: false

      def mails
        object.mails?
      end

      def mail_from
        object.read_attribute(:mail_from)
      end

      def dynamic_client_scopes
        object.dynamic_client_scopes.presence && Scopes.list(object.dynamic_client_scopes)
      end

      def signing_keys
        object.signing_keys.published
      end
    end
  end
end
