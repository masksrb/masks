module Masks
  module Server
    module Manage
      module Types
        class ActorType < BaseObject
          field :uuid, ID, null: false
          field :identifier, String, null: false
          field :nickname, String
          field :email, String
          field :email_verified, Boolean, null: false
          field :phone, String
          field :phone_verified, Boolean, null: false
          field :signed_up_at, GraphQL::Types::ISO8601DateTime
          field :pending_approval, Boolean, null: false
          field :suspended_at, GraphQL::Types::ISO8601DateTime
          field :external_id, String
          field :activated, Boolean, null: false
          field :invited_at, GraphQL::Types::ISO8601DateTime
          field :scopes, [ String ], null: false
          field :otp_enabled, Boolean, null: false
          field :email_codes_enabled, Boolean, null: false
          field :text_codes_enabled, Boolean, null: false
          field :backup_codes_remaining, Integer, null: false
          field :passkeys, [ PasskeyType ], null: false
          field :sessions, [ "Masks::Server::Manage::Types::SessionType" ], null: false
          field :devices, [ "Masks::Server::Manage::Types::DeviceType" ], null: false
          field :connections, [ "Masks::Server::Manage::Types::ConnectionType" ], null: false
          field :consents, [ "Masks::Server::Manage::Types::ConsentType" ], null: false
          field :tokens, [ "Masks::Server::Manage::Types::TokenType" ], null: false

          field :events, [ "Masks::Server::Manage::Types::EventType" ], null: false do
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

          def phone_verified
            object.phone_verified_at.present?
          end

          def pending_approval
            object.pending_approval_at.present?
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

          def email_codes_enabled
            object.email_factor?
          end

          def text_codes_enabled
            object.phone_factor?
          end

          def avatars
            Masks::Server::Avatars.urls(object, subject: object.uuid)
          end

          def photo_uploaded
            Masks::Server::Avatars.photo(object).present?
          end

          def passkeys
            Masks::Server::Passkey.where(actor_id: object.id).includes(:authenticator).newest_first
          end

          def sessions
            Masks::Server::Session.live.where(actor_id: object.id).order(created_at: :desc)
          end

          def devices
            Masks::Server::Device.for_actor(object).newest_first
          end

          def connections
            Masks::Server::Connection.live.where(actor_id: object.id).includes(:provider).order(created_at: :desc)
          end

          def consents
            Masks::Server::Consent.live.where(actor_id: object.id).includes(:client).order(updated_at: :desc)
          end

          def tokens
            Masks::Server::Token.where(kind: TokenType::GRANTS, actor_id: object.id)
                   .live
                   .includes(:client, :device)
                   .order(created_at: :desc)
          end

          def events(limit: nil)
            Masks::Server::Event
              .where(actor_id: object.id)
              .newest_first
              .includes(:by, :client, :device)
              .limit(Masks::Server::Event.bounded(limit))
          end
        end
      end
    end
  end
end
