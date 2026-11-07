module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Activity
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            SPAN = 30
            LONGEST = 90

            included do
              field :tally, TallyType, null: false

              field :activity, [ ActivityDayType ], null: false do
                argument :days, Integer, required: false
              end

              field :events, [ EventType ], null: false do
                argument :actor, ID, required: false
                argument :client, ID, required: false
                argument :device, ID, required: false
                argument :action, String, required: false
                argument :grave, Boolean, required: false
                argument :organization, ID, required: false
                argument :since, GraphQL::Types::ISO8601DateTime, required: false,
                                                                   description: "Only events recorded at or after this time."
                argument :after_id, ID, required: false
                argument :limit, Integer, required: false
              end

              field :event_count, Integer, null: false do
                argument :actor, ID, required: false
                argument :client, ID, required: false
                argument :device, ID, required: false
                argument :action, String, required: false
                argument :grave, Boolean, required: false
                argument :organization, ID, required: false
                argument :since, GraphQL::Types::ISO8601DateTime, required: false,
                                                                   description: "Only events recorded at or after this time."
              end

              field :event_actions, [ EventActionType ], null: false

              field :event_streams, [ EventStreamType ], null: false do
                argument :archived, Boolean, required: false
              end
            end

            def tally
              {
                actors: Actor.count,
                clients: Client.active.count,
                devices: Masks::Server::Device.allowed.count,
                organizations: Masks::Server::Organization.active.count
              }
            end

            def activity(days: nil)
              span = [ days&.clamp(1, LONGEST) || SPAN, LONGEST ].min
              from = Date.current - (span - 1)

              counted = Session
                .where(authenticated_at: from.beginning_of_day..)
                .group(Arel.sql("DATE(authenticated_at)"))
                .count

              (from..Date.current).map do |on|
                { date: on, sign_ins: counted[on] || 0 }
              end
            end

            def events(after_id: nil, limit: nil, **filters)
              scope = event_scope(**filters).newest_first.includes(:actor, :by, :client, :device, :organization)
              scope = scope.after(after_id) if after_id.present?

              scope.limit(Masks::Server::Event.bounded(limit))
            end

            def event_count(**filters)
              event_scope(**filters).count
            end

            def event_actions
              Masks::Server::Event::ACTIONS.sort
            end

            def event_streams(archived: false)
              Masks::Server::EventStream.listed(archived).order(:name)
            end

            private

              def event_scope(actor: nil, client: nil, device: nil, action: nil, grave: false, organization: nil, since: nil)
                subject = actor.present? ? Actor.find_by(uuid: actor) : nil
                group = organization.present? ? Masks::Server::Organization.find_by(key: organization) : nil

                return Masks::Server::Event.none if organization.present? && group.nil?

                held = client.present? ? Client.find_by(client_id: client) : nil
                seen = device.present? ? Masks::Server::Device.find_by(id: device) : nil

                return Masks::Server::Event.none if actor.present? && subject.nil?
                return Masks::Server::Event.none if client.present? && held.nil?
                return Masks::Server::Event.none if device.present? && seen.nil?

                scope = Masks::Server::Event.all
                scope = scope.where(actor: subject) if subject
                scope = scope.where(client: held) if held
                scope = scope.where(device: seen) if seen
                scope = scope.where(organization: group) if group
                scope = scope.where(action: action) if action.present?
                scope = scope.where(action: Masks::Server::Event::GRAVE) if grave
                scope = scope.where(created_at: since..) if since

                scope
              end
          end
        end
      end
    end
  end
end
