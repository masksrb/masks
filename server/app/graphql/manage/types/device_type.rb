module Manage
  module Types
    class DeviceType < BaseObject
      field :id, ID, null: false
      field :label, String, null: false
      field :name, String
      field :category, String, null: false
      field :known, Boolean, null: false
      field :user_agent, String
      field :ip_address, String
      field :last_seen_at, GraphQL::Types::ISO8601DateTime, null: false
      field :blocked_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      field :actors, [ ActorType ], null: false
      field :sessions, [ "Manage::Types::SessionType" ], null: false

      def known
        object.known?
      end

      def actors
        Actor.where(id: object.sessions.select(:actor_id)).order(:nickname)
      end

      def sessions
        object.sessions.live.includes(:actor).order(created_at: :desc)
      end
    end
  end
end
