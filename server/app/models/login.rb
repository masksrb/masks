class Login
  STATES = [
    LoginStates::Setup,
    LoginStates::Invitation,
    LoginStates::PasswordReset,
    LoginStates::Passkey,
    LoginStates::Provider,
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

  attr_reader :store, :updates, :event, :prompt, :warnings, :request, :session, :device, :refusal, :rid
  attr_accessor :redirect_to

  def initialize(store:, request: nil, session: nil, device: nil, rid: nil, event: nil, updates: {})
    @store = store
    @request = request
    @session = session
    @device = device
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
    disowned = actor&.id != record&.id

    remove_instance_variable(:@actor) if defined?(@actor)
    store["actor_id"] = record&.id

    disown! if disowned
  end

  def disown!
    store.delete("factors")
    store.delete("amr")
  end

  def factors
    store["factors"] ||= {}
  end

  def amr
    store["amr"] ||= []
  end

  def noted!(*methods)
    amr.concat(methods.map(&:to_s))
    amr.uniq!
    amr
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

    touched?(:second_factor) || signed_in? || remembered?(:second_factor)
  end

  def remembered?(factor)
    return false if device.nil? || actor.nil?

    device.remembers?(actor, factor)
  end

  def remember!(factor, expiry: DeviceFactor::LIFETIME)
    Event.record!(Event::DEVICE_TRUSTED, actor: actor, device: device, factor: factor.to_s)

    DeviceFactor.remember!(device: device, actor: actor, factor: factor, expiry: expiry)
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

  def messages
    warnings.filter_map do |key|
      notice = I18n.t("logins.notices.#{key}", default: nil)
      text = notice || I18n.t("logins.warnings.#{key}", default: nil)

      next unless text

      { "key" => key, "text" => text, "tone" => notice ? "note" : "note note-bad" }
    end
  end

  def copy
    key = prompt.to_s.tr("-", "_")
    shared = I18n.t("logins.shared", default: {})
    named = key.present? ? I18n.t("logins.#{key}", default: {}) : {}

    shared.merge(named.is_a?(Hash) ? named : {}).transform_keys(&:to_s)
  end

  def as_json(*)
    base = {
      "prompt" => prompt,
      "settled" => settled?,
      "copy" => copy,
      "warnings" => warnings,
      "messages" => messages,
      "identifier" => identifier,
      "rid" => rid,
      "docs" => Rails.configuration.masks.docs_url,
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
