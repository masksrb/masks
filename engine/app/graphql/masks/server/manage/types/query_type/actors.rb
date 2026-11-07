module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Actors
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :actors, [ ActorType ], null: false do
                argument :search, String, required: false
                argument :activated, Boolean, required: false
                argument :holds, String, required: false
                argument :pending_approval, Boolean, required: false
                argument :recovery_requested, Boolean, required: false
                argument :suspended, Boolean, required: false
                argument :after_id, ID, required: false
                argument :limit, Integer, required: false
              end

              field :actor_count, Integer, null: false do
                argument :search, String, required: false
                argument :activated, Boolean, required: false
                argument :holds, String, required: false
                argument :pending_approval, Boolean, required: false
                argument :recovery_requested, Boolean, required: false
                argument :suspended, Boolean, required: false
              end

              field :actor, ActorType do
                argument :uuid, ID
              end

              field :sessions, [ SessionType ], null: false do
                argument :actor, ID, required: false
                argument :limit, Integer, required: false
              end

              field :devices, [ DeviceType ], null: false do
                argument :actor, ID, required: false
                argument :blocked, Boolean, required: false
                argument :unattached, Boolean, required: false
                argument :agent, String, required: false
                argument :limit, Integer, required: false
              end

              field :device, DeviceType do
                argument :id, ID
              end

              field :minimum_password, Integer, null: false
            end

            def actors(after_id: nil, limit: nil, **filters)
              scope = actor_scope(**filters).newest_first
              scope = scope.after(Actor.find_by(uuid: after_id)&.id) if after_id.present?

              scope.limit(bounded(limit))
            end

            def actor_count(**filters)
              actor_scope(**filters).count
            end

            def actor(uuid:)
              Actor.find_by(uuid: uuid)
            end

            def sessions(actor: nil, limit: nil)
              scope = Session.live.includes(:actor).order(created_at: :desc)
              scope = scope.where(actor: Actor.find_by(uuid: actor)) if actor.present?

              scope.limit(bounded(limit))
            end

            def devices(actor: nil, blocked: nil, unattached: nil, agent: nil, limit: nil)
              scope = Masks::Server::Device.newest_first
              scope = scope.for_actor(Masks::Server::Actor.find_by(uuid: actor)) if actor.present?
              scope = blocked ? scope.blocked : scope.allowed unless blocked.nil?
              scope = scope.where.not(id: signed_in_on) if unattached
              scope = scope.agent_like(agent) if agent.present?

              scope.limit(bounded(limit))
            end

            def device(id:)
              Masks::Server::Device.find_by(id: id)
            end

            def minimum_password
              Actor::MINIMUM_PASSWORD
            end

            private

              def actor_scope(search: nil, activated: nil, holds: nil, pending_approval: nil, recovery_requested: nil,
                              suspended: nil)
                scope = Actor.all

                if search.present?
                  term = "%#{Actor.sanitize_sql_like(search.strip)}%"
                  scope = scope.where("nickname ILIKE :term OR email ILIKE :term OR name ILIKE :term", term: term)
                end

                scope = activated ? scope.where.not(activated_at: nil) : scope.where(activated_at: nil) unless activated.nil?
                scope = scope.holding(holds) if holds.present?
                scope = pending_approval ? scope.where.not(pending_approval_at: nil) : scope.where(pending_approval_at: nil) unless pending_approval.nil?
                scope = suspended ? scope.where.not(suspended_at: nil) : scope.where(suspended_at: nil) unless suspended.nil?
                unless recovery_requested.nil?
                  scope = recovery_requested ? scope.where.not(recovery_requested_at: nil) : scope.where(recovery_requested_at: nil)
                end

                scope
              end

              def signed_in_on
                Session.where.not(device_id: nil).select(:device_id)
              end
          end
        end
      end
    end
  end
end
