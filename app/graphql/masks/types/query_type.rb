#/ frozen_string_literal: true

module Masks::Types
  class QueryType < BaseObject
    field :actor,
          ActorType,
          null: true,
          managers_only: true,
          description: "Fetches an actor given its identifier." do
      argument :identifier,
               String,
               required: false,
               description: "identifier of the actor."
      argument :id, ID, required: false, description: "id of the actor."
    end

    def actor(identifier: nil, id: nil)
      actor =
        if identifier
          Masks.actors.identify(identifier, required: true)
        else
          Masks.actors.identify(key: id, required: true)
        end

      actor if actor&.persisted?
    end

    field :actors,
          ActorType.connection_type,
          null: false,
          managers_only: true do
      argument :identifier, String, required: false
    end

    def actors(**args)
      scope = Masks.actors.order(created_at: :desc)

      if args[:identifier]
        scope =
          scope.left_outer_joins(:emails).where(
            "masks_emails.address LIKE :email OR nickname LIKE :nickname OR name LIKE :name",
            email: "%#{Masks.actors.sanitize_sql_like(args[:identifier])}%",
            name: "%#{Masks.actors.sanitize_sql_like(args[:identifier])}%",
            nickname: "#{Masks.actors.sanitize_sql_like(args[:identifier])}%",
          )
      end

      scope
    end

    field :client,
          ClientType,
          null: true,
          managers_only: true,
          description: "Fetches a client given its id." do
      argument :id, ID, required: true, description: "id of the client."
    end

    def client(id:)
      Masks.clients.discover(id)
    end

    field :clients,
          ClientType.connection_type,
          null: false,
          managers_only: true do
      argument :name, String, required: false
      argument :actor, String, required: false
      argument :device, String, required: false
    end

    def clients(**args)
      scope = Masks::Client.includes(:actors, :devices).order(created_at: :desc)

      if args[:name]
        scope =
          scope.where(
            "name LIKE ?",
            "#{Masks::Client.sanitize_sql_like(args[:name])}%",
          )
      elsif args[:query]
        scope =
          scope.where(
            "name LIKE ? OR key = ?",
            "#{Masks::Client.sanitize_sql_like(args[:query])}%",
            args[:query],
          )
      end

      if args[:actor]
        actor = Masks.actors.identify(args[:actor], required: true)
        scope = scope.where(actors: { id: actor.id })
      end

      if args[:device]
        device = Masks::Device.find_by(public_id: args[:device])
        scope = scope.where(devices: { id: device&.id })
      end

      scope
    end

    field :providers,
          ProviderType.connection_type,
          null: false,
          managers_only: true do
      argument :id, String, required: false
      argument :name, String, required: false
      argument :type, String, required: false
    end

    def providers(**args)
      scope = Masks::Provider.all

      if args[:name]
        scope =
          scope.where(
            "name like ?",
            "#{Masks::Provider.sanitize_sql_like(args[:name])}%",
          )
      elsif args[:query]
        scope =
          scope.where(
            "lower(name) like ? OR key = ?",
            "#{Masks::Provider.sanitize_sql_like(args[:query].downcase)}%",
            args[:query],
          )
      end

      scope = scope.where(type: args[:type]) if args[:type]

      scope
    end

    field :provider, ProviderType, null: true, managers_only: true do
      argument :id, String, required: false
    end

    def provider(**args)
      Masks.provider(args[:id])
    end

    field :server,
          ServerType,
          description: "Returns the server settings",
          managers_only: true,
          null: true

    def server
      Masks.conf if Masks.mode.server?
    end

    field :device,
          DeviceType,
          null: true,
          managers_only: true,
          description: "Fetches a device given its id." do
      argument :id, String, required: true, description: "id of the device."
    end

    def device(id:)
      Masks::Device.find_by(public_id: id)
    end

    field :devices,
          DeviceType.connection_type,
          null: false,
          managers_only: true do
      argument :id, String, required: false
      argument :actor, String, required: false
      argument :blocked, Boolean, required: false
    end

    def devices(**args)
      scope = Masks::Device.includes(:actors).order(created_at: :desc)

      if args[:id]
        scope =
          scope.where(
            "public_id LIKE ?",
            "#{Masks::Device.sanitize_sql_like(args[:id])}%",
          )
      end

      if args[:actor]
        actor = Masks.actors.identify(args[:actor], required: true)
        scope = scope.where(actors: { id: actor&.id })
      end

      if args.key?(:blocked)
        scope =
          (
            if args[:blocked]
              scope.where.not(blocked_at: nil)
            else
              scope.where(blocked_at: nil)
            end
          )
      end

      scope
    end

    field :tokens,
          TokenType.connection_type,
          null: false,
          managers_only: true do
      argument :id, String, required: false
      argument :name, String, required: false
      argument :actor, String, required: false
      argument :device, String, required: false
      argument :client, String, required: false
    end

    def tokens(**args)
      scope = Masks::Token.includes(:actor, :client).order(created_at: :desc)

      if args[:query]
        scope =
          scope.where(
            "name like ? OR key=?",
            "#{Masks::Token.sanitize_sql_like(args[:query])}%",
            args[:query],
          ).or(Masks::Token.where(secret: args[:query]))
      else
        scope = scope.where(key: args[:id]) if args[:id]
        scope =
          scope.where(
            "name like ?",
            "#{Masks::Token.sanitize_sql_like(args[:name])}%",
          ) if args[:name]
      end

      if args[:actor]
        actor = Masks.actors.identify(args[:actor], required: true)
        scope = scope.where(actor:)
      end

      scope =
        scope.where(client: Masks.clients.discover(args[:client])) if args[
        :client
      ]

      if args[:device]
        scope =
          scope.where(device: Masks::Device.find_by(public_id: args[:device]))
      end

      scope
    end

    field :token,
          TokenType,
          null: true,
          managers_only: true,
          description: "Fetches a token given its key" do
      argument :id, String, required: true, description: "id of the token"
    end

    def token(id:)
      Masks::Token.find_by(key: id)
    end

    field :emails, EmailType.connection_type, null: false

    def emails
      Masks::Email.order(created_at: :desc).includes(:actor)
    end

    field :phones, PhoneType.connection_type, null: false

    def phones
      Masks::Phone.order(created_at: :desc).includes(:actor)
    end

    field :search, SearchType, null: true, managers_only: true do
      argument :query,
               String,
               required: true,
               description: "search query to use for filtering data"
    end

    def search(**args)
      query = args[:query]
      query = "" unless query&.present?
      query.strip!

      return unless query.length > 0

      actors = self.actors(identifier: query)
      clients = self.clients(query:)
      providers = self.providers(query:)
      tokens = self.tokens(query:)
      result = { actors:, clients:, tokens:, providers:, query: }
      result
    end

    private

    def find_clients(query)
      return Masks::Client.none if !query

      Masks::Client.where(
        "key LIKE ? OR name LIKE ?",
        "#{query}%",
        "%#{query}%",
      ).order(created_at: :desc)
    end

    def parse_query(query)
      return "" unless query&.present?

      query.strip
    end
  end
end
