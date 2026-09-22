module Masks
  module Server
    module Manage
      module Types
        class EventType < BaseObject
          field :id, ID, null: false
          field :action, String, null: false
          field :label, String, null: false
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :ip_address, String
          field :user_agent, String
          field :details, GraphQL::Types::JSON, null: false

          field :actor, ActorType
          field :by, ActorType
          field :client, ClientType
          field :device, DeviceType

          def label
            I18n.t("events.actions.#{object.action}", default: object.action)
          end
        end
      end
    end
  end
end
