module Manage
  module Types
    class ActorType < BaseObject
      field :uuid, ID, null: false
      field :nickname, String, null: false
      field :email, String
      field :email_verified, Boolean, null: false
      field :activated, Boolean, null: false
      field :invited_at, GraphQL::Types::ISO8601DateTime
      field :scopes, [ String ], null: false
      field :otp_enabled, Boolean, null: false
      field :backup_codes_remaining, Integer, null: false
      field :passkeys, [ PasskeyType ], null: false
      field :sessions, [ "Manage::Types::SessionType" ], null: false
      field :devices, [ "Manage::Types::DeviceType" ], null: false
      field :connections, [ "Manage::Types::ConnectionType" ], null: false
      field :consents, [ "Manage::Types::ConsentType" ], null: false
      field :tokens, [ "Manage::Types::TokenType" ], null: false

      field :events, [ "Manage::Types::EventType" ], null: false do
        argument :limit, Integer, required: false
      end
      field :backup_codes_generated_at, GraphQL::Types::ISO8601DateTime
      field :last_login_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :avatars, AvatarsType, null: false
      field :photo_uploaded, Boolean, null: false

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

      def activated
        object.activated?
      end

      def invited_at
        return nil if object.activated?

        Invitation.where(actor_id: object.id).live.maximum(:created_at)
      end

      def scopes
        object.scope_list
      end

      def otp_enabled
        object.otp?
      end

      def avatars
        ::Avatars.urls(object, subject: object.uuid)
      end

      def photo_uploaded
        ::Avatars.photo(object).present?
      end

      def passkeys
        ::Passkey.where(actor_id: object.id).includes(:authenticator).newest_first
      end

      def sessions
        ::Session.live.where(actor_id: object.id).order(created_at: :desc)
      end

      def devices
        ::Device.for_actor(object).newest_first
      end

      def connections
        ::Connection.live.where(actor_id: object.id).includes(:provider).order(created_at: :desc)
      end

      def consents
        ::Consent.live.where(actor_id: object.id).includes(:client).order(updated_at: :desc)
      end

      def tokens
        ::Token.where(type: TokenType::GRANTS, actor_id: object.id)
               .live
               .includes(:client, :device)
               .order(created_at: :desc)
      end

      def events(limit: nil)
        ::Event
          .where(actor_id: object.id)
          .newest_first
          .includes(:by, :client, :device)
          .limit(::Event.bounded(limit))
      end
    end
  end
end
