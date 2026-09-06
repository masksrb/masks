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

      field :devices, [ DeviceType ], null: false do
        argument :actor, ID, required: false
        argument :blocked, Boolean, required: false
        argument :unattached, Boolean, required: false
        argument :limit, Integer, required: false
      end

      field :device, DeviceType do
        argument :id, ID
      end

      field :namespaces, [ NamespaceType ], null: false

      field :providers, [ ProviderType ], null: false do
        argument :archived, Boolean, required: false
      end

      field :provider, ProviderType do
        argument :key, ID
      end

      field :scopes_supported, [ String ], null: false

      field :minimum_password, Integer, null: false

      field :tally, TallyType, null: false

      field :activity, [ ActivityDayType ], null: false do
        argument :days, Integer, required: false
      end

      field :events, [ EventType ], null: false do
        argument :actor, ID, required: false
        argument :client, ID, required: false
        argument :action, String, required: false
        argument :grave, Boolean, required: false
        argument :after_id, ID, required: false
        argument :limit, Integer, required: false
      end

      field :event_actions, [ String ], null: false

      LIMIT = 50
      CEILING = 200
      SPAN = 30
      LONGEST = 90

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
        scope = scope.includes(:approved_by, :namespaces).order(created_at: :desc)

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

      def devices(actor: nil, blocked: nil, unattached: nil, limit: nil)
        scope = ::Device.newest_first
        scope = scope.for_actor(::Actor.find_by(uuid: actor)) if actor.present?
        scope = blocked ? scope.where.not(blocked_at: nil) : scope.allowed unless blocked.nil?
        scope = scope.where.not(id: signed_in_on) if unattached

        scope.limit(bounded(limit))
      end

      def device(id:)
        ::Device.find_by(id: id)
      end

      def namespaces
        Namespace.includes(:client).order(:name)
      end

      def providers(archived: false)
        scope = archived ? ::Provider.where.not(archived_at: nil) : ::Provider.active

        scope.order(:name)
      end

      def provider(key:)
        ::Provider.find_by(key: key)
      end

      def scopes_supported
        Scopes::DESCRIBED.keys
      end

      def minimum_password
        Actor::MINIMUM_PASSWORD
      end

      def tally
        {
          actors: Actor.count,
          clients: Client.active.count,
          sessions: Session.live.count,
          devices: ::Device.allowed.count
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

      def events(actor: nil, client: nil, action: nil, grave: false, after_id: nil, limit: nil)
        subject = actor.present? ? Actor.find_by(uuid: actor) : nil
        held = client.present? ? Client.find_by(client_id: client) : nil

        return ::Event.none if actor.present? && subject.nil?
        return ::Event.none if client.present? && held.nil?

        scope = ::Event.newest_first.includes(:actor, :by, :client, :device)
        scope = scope.where(actor: subject) if subject
        scope = scope.where(client: held) if held
        scope = scope.where(action: action) if action.present?
        scope = scope.where(action: ::Event::GRAVE) if grave
        scope = scope.after(after_id) if after_id.present?

        scope.limit(::Event.bounded(limit))
      end

      def event_actions
        ::Event::ACTIONS.sort
      end

      private

        def signed_in_on
          Session.where.not(device_id: nil).select(:device_id)
        end

        def bounded(limit)
          [ limit || LIMIT, CEILING ].min
        end
    end
  end
end
