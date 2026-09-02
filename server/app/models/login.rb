class Login
  STATES = [
    LoginStates::Setup,
    LoginStates::Invitation,
    LoginStates::Identifier,
    LoginStates::Password,
    LoginStates::FirstFactor,
    LoginStates::OneTimePassword,
    LoginStates::BackupCode,
    LoginStates::SecondFactor,
    LoginStates::Consent
  ].freeze

  SETTLED = "settled".freeze

  def self.permitted_updates
    STATES.flat_map { |state| state.declared_updates }.uniq
  end

  attr_reader :store, :updates, :event, :prompt, :warnings, :request, :session, :refusal, :rid

  def initialize(store:, request: nil, session: nil, rid: nil, event: nil, updates: {})
    @store = store
    @request = request
    @session = session
    @rid = rid
    @event = event.presence&.to_s
    @updates = (updates || {}).stringify_keys
    @warnings = []
  end

  def client
    request&.client
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
    @actor = id ? Actor.find_by(id: id) : session&.actor
  end

  def actor=(record)
    remove_instance_variable(:@actor) if defined?(@actor)
    store["actor_id"] = record&.id
  end

  def factors
    store["factors"] ||= {}
  end

  def touched?(key)
    until_at = stamp(key, "until")

    until_at.present? && until_at > Time.current
  end

  def factored_at(key)
    stamp(key, "at")
  end

  PRECISION = 6

  def factored!(key, expiry:)
    now = Time.current

    factors[key.to_s] = {
      "at" => now.iso8601(PRECISION),
      "until" => (now + expiry).iso8601(PRECISION)
    }
  end

  def expire!(key)
    store["factors"]&.delete(key.to_s)
  end

  def authenticated_at
    factored_at(:first_factor) || session&.authenticated_at
  end

  def signed_in?
    session.present?
  end

  def reauthenticating?
    return false unless request&.reauthenticate?

    authenticated_at.nil? || authenticated_at < request.created_at
  end

  def stale?
    age = request&.max_age
    return false if age.nil?

    authenticated_at.nil? || authenticated_at < age.to_i.seconds.ago
  end

  def first_factored?
    return false if reauthenticating? || stale?

    touched?(:first_factor) || signed_in?
  end

  def second_factored?
    return false if reauthenticating? || stale?

    touched?(:second_factor) || signed_in?
  end

  def warn!(*keys)
    warnings.concat(keys.compact.map(&:to_s))
    warnings.uniq!
  end

  def settled?
    prompt == SETTLED
  end

  def prompted?
    prompt.present? && !settled?
  end

  def refused?
    refusal.present?
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
  rescue LoginState::Refused => denial
    @refusal = denial
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
    base = {
      "prompt" => prompt,
      "settled" => settled?,
      "warnings" => warnings,
      "identifier" => identifier,
      "rid" => rid,
      "actor" => actor && { "nickname" => actor.nickname, "name" => actor.name },
      "client" => client && { "name" => client.name, "id" => client.client_id },
      "tenant" => tenant && { "name" => tenant.name }
    }

    states.reduce(base) { |json, state| state.enabled? ? json.merge(state.as_json) : json }
  end

  private

    def stamp(key, field)
      value = store["factors"]&.dig(key.to_s, field)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def states
      states_by_key.values
    end

    def states_by_key
      @states_by_key ||= STATES.index_by(&:key).transform_values { |cls| cls.new(self) }
    end
end
