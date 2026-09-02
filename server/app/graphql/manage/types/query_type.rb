module Manage
  module Types
    class QueryType < BaseObject
      field :viewer, ActorType, null: false
      field :tenant, TenantType, null: false

      field :actors, [ ActorType ], null: false do
        argument :search, String, required: false
        argument :limit, Integer, required: false
      end

      field :actor, ActorType do
        argument :uuid, ID
      end

      field :clients, [ ClientType ], null: false do
        argument :search, String, required: false
        argument :archived, Boolean, required: false
        argument :limit, Integer, required: false
      end

      field :client, ClientType do
        argument :client_id, ID
      end

      field :sessions, [ SessionType ], null: false do
        argument :actor, ID, required: false
        argument :limit, Integer, required: false
      end

      field :scopes_supported, [ String ], null: false

      LIMIT = 50
      CEILING = 200

      def viewer
        context[:actor]
      end

      def tenant
        Current.tenant
      end

      def actors(search: nil, limit: nil)
        scope = Actor.order(created_at: :desc)

        if search.present?
          term = "%#{Actor.sanitize_sql_like(search.strip)}%"
          scope = scope.where("nickname ILIKE :term OR email ILIKE :term OR name ILIKE :term", term: term)
        end

        scope.limit(bounded(limit))
      end

      def actor(uuid:)
        Actor.find_by(uuid: uuid)
      end

      def clients(search: nil, archived: false, limit: nil)
        scope = archived ? Client.where.not(archived_at: nil) : Client.active
        scope = scope.includes(:approved_by).order(created_at: :desc)

        if search.present?
          term = "%#{Client.sanitize_sql_like(search.strip)}%"
          scope = scope.where("name ILIKE :term OR client_id = :exact", term: term, exact: search.strip)
        end

        scope.limit(bounded(limit))
      end

      def client(client_id:)
        Client.find_by(client_id: client_id)
      end

      def sessions(actor: nil, limit: nil)
        scope = Session.live.includes(:actor).order(created_at: :desc)
        scope = scope.where(actor: Actor.find_by(uuid: actor)) if actor.present?

        scope.limit(bounded(limit))
      end

      def scopes_supported
        Scopes::DESCRIBED.keys
      end

      private

        def bounded(limit)
          [ limit || LIMIT, CEILING ].min
        end
    end
  end
end
