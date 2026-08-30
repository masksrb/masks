class Login
  STATES = [
    LoginStates::Identifier,
    LoginStates::Password,
    LoginStates::FirstFactor,
    LoginStates::OneTimePassword,
    LoginStates::SecondFactor
  ].freeze

  SETTLED = "settled".freeze

  attr_reader :store, :updates, :event, :prompt, :warnings

  def initialize(store:, client: nil, event: nil, updates: {})
    @store = store
    @client = client
    @event = event.presence&.to_s
    @updates = (updates || {}).stringify_keys
    @warnings = []
  end

  def client
    @client
  end

  def tenant
    Current.tenant
  end

  def identifier
    store["identifier"]
  end

  def identifier=(value)
    store["identifier"] = value.presence
  end

  def actor
    return @actor if defined?(@actor)

    id = store["actor_id"]
    @actor = id ? Actor.find_by(id: id) : nil
  end

  def actor=(record)
    remove_instance_variable(:@actor) if defined?(@actor)
    store["actor_id"] = record&.id
  end

  def factors
    store["factors"] ||= {}
  end

  def touched?(key)
    at = factors[key.to_s]
    return false if at.blank?

    Time.iso8601(at) > Time.current
  rescue ArgumentError
    false
  end

  def factored!(key, expiry:)
    factors[key.to_s] = expiry.from_now.iso8601
  end

  def expire!(key)
    factors.delete(key.to_s)
  end

  def warn!(*keys)
    warnings.concat(keys.compact.map(&:to_s))
    warnings.uniq!
  end

  def settled?
    prompt == SETTLED
  end

  def update
    states.each(&:reload!)
    states.each { |state| state.event!(event) } if event
    states.each(&:factor!)

    @prompt = SETTLED
    self
  rescue LoginState::PromptRequired => denial
    @prompt = denial.prompt
    self
  ensure
    states.each(&:cleanup!)
  end

  def start_over!
    states.each(&:start_over!)
    store.replace({})
    self
  end

  def state(key)
    states_by_key.fetch(key.to_s)
  end

  def as_json(*)
    {
      "prompt" => prompt,
      "settled" => settled?,
      "warnings" => warnings,
      "identifier" => identifier,
      "actor" => actor && { "nickname" => actor.nickname, "name" => actor.name },
      "client" => client && { "name" => client.name, "id" => client.client_id },
      "tenant" => tenant && { "name" => tenant.name }
    }
  end

  private

    def states
      states_by_key.values
    end

    def states_by_key
      @states_by_key ||= STATES.index_by(&:key).transform_values { |cls| cls.new(self) }
    end
end
