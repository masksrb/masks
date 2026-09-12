module Apps
  Held = Data.define(:client, :scopes, :consent) do
    def name
      client.name
    end

    def client_id
      client.client_id
    end

    def scope_list
      Scopes.list(scopes)
    end

    def audience
      consent&.audience || []
    end
  end

  def self.held_by(actor)
    consents = Consent.live.where(actor: actor).includes(:client).index_by(&:client_id)
    scopes = token_scopes(actor)

    ids = (consents.keys + scopes.keys).uniq
    clients = Client.where(id: ids).index_by(&:id)

    ids.filter_map do |id|
      client = clients[id]
      next if client.nil?

      consent = consents[id]
      held = consent ? Scopes.list(consent.scopes) | scopes.fetch(id, []) : scopes.fetch(id, [])

      Held.new(client: client, scopes: Scopes.join(held), consent: consent)
    end.sort_by { |app| app.name.to_s.downcase }
  end

  def self.token_scopes(actor)
    Token.live.where(actor: actor, type: [ "AccessToken", "RefreshToken" ])
         .where.not(client_id: nil)
         .pluck(:client_id, :scopes)
         .each_with_object({}) do |(client_id, scopes), held|
      held[client_id] = (held[client_id] || []) | Scopes.list(scopes)
    end
  end
end
