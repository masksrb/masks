class Login
  STATES = [
    LoginStates::Invitation,
    LoginStates::PasswordReset,
    LoginStates::Passkey,
    LoginStates::Provider,
    LoginStates::Identifier,
    LoginStates::Inbox,
    LoginStates::Signup,
    LoginStates::Password,
    LoginStates::FirstFactor,
    LoginStates::Suspension,
    LoginStates::OneTimePassword,
    LoginStates::BackupCode,
    LoginStates::SecondFactor,
    LoginStates::Enrolment,
    LoginStates::Confirmation,
    LoginStates::Configure,
    LoginStates::Delegation,
    LoginStates::Consent
  ].freeze

  SETTLED = "settled".freeze

  def self.permitted_updates
    STATES.flat_map { |state| state.declared_updates }.uniq
  end

  def self.limit_for(event)
    STATES.each do |state|
      limit = state.declared_limits[event.to_s]
      return limit if limit
    end

    nil
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
    @warning_fields = {}
  end

  def client
    request&.client
  end

  def tenant
    Current.tenant
  end

  def policy
    @policy ||= first_run? ? SignInPolicy.first_run : SignInPolicy.for(client: client, tenant: tenant)
  end

  def first_run?
    return @first_run if defined?(@first_run)

    @first_run = !Actor.exists?
  end

  def first_run!
    remove_instance_variable(:@first_run) if defined?(@first_run)
    remove_instance_variable(:@policy) if defined?(@policy)
  end

  def journey
    signed_up = store[LoginStates::Signup::SIGNED_UP]
    first = signed_up ? signed_up["first_run"] : first_run?

    return nil unless signed_up || state("signup").enabled?

    { "firstRun" => first, "steps" => LoginStates::Signup.steps(first, policy) }
  end

  def surface
    prompt == "consent" || (journey && !settled?) ? "grant" : "challenge"
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
    factored_at(:first_factor) || (signed_in? ? session.authenticated_at : nil)
  end

  def signed_in?
    session.present? && actor.present? && session.actor_id == actor.id
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
    return false if reauthenticating? || stale? || actor.nil?

    touched?(:first_factor) || signed_in?
  end

  def second_factored?
    return false if reauthenticating? || stale? || actor.nil?

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

  def warn!(*keys, field: nil)
    @as_json = nil

    keys.compact.map(&:to_s).each do |key|
      warnings << key unless warnings.include?(key)
      @warning_fields[key] = field.to_s if field
    end
  end

  def carried
    warnings.map { |key| [ key, @warning_fields[key] ] }
  end

  def carry!(held)
    Array(held).each { |key, field| warn!(key, field: field) }
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
    @as_json = nil
    forget_vanished_actor!
    states.each(&:reload!)
    states.each { |state| state.event!(event) } if event
    @prompting = nil

    states.each do |state|
      @prompting = state
      state.factor!
    end

    @prompting = nil
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
    @as_json = nil
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

      { "key" => key, "text" => text, "tone" => notice ? "note" : "note note-bad", "field" => @warning_fields[key] }.compact
    end
  end

  def message_for(field)
    messages.find { |message| message["field"] == field.to_s }
  end

  def copy
    key = prompt.to_s.tr("-", "_")
    shared = I18n.t("logins.shared", default: {})
    shared = shared.merge(I18n.t("logins.signing_up", default: {})) if journey
    named = key.present? ? I18n.t("logins.#{key}", default: {}) : {}

    shared.merge(named.is_a?(Hash) ? named : {}).transform_keys(&:to_s)
  end

  def as_json(*)
    @as_json ||= build_json
  end

  def client_json
    return nil if client.nil?

    {
      "name" => client.name,
      "id" => client.client_id,
      "logo" => client.logo_url(actor),
      "site" => client.link(:client_uri),
      "terms" => client.link(:tos_uri),
      "privacy" => client.link(:policy_uri),
      "returnsTo" => SectorIdentifier.host(request.redirect_uri)
    }.compact
  end

  private

    def build_json
      base = {
        "prompt" => prompt,
        "settled" => settled?,
        "copy" => copy,
        "warnings" => warnings,
        "messages" => messages,
        "identifier" => identifier,
        "rid" => rid,
        "docs" => Rails.configuration.masks.docs_url,
        "actor" => actor && { "nickname" => actor.nickname, "name" => actor.name,
                              "identifier" => actor.identifier },
        "person" => person_json,
        "client" => client_json,
        "tenant" => tenant && { "name" => tenant.name },
        "journey" => journey,
        "surface" => surface
      }

      answering.reduce(base) { |json, state| state.enabled? ? json.merge(state.as_json) : json }
    end

    def person_json
      return nil if actor.nil? || authenticated_at.nil?

      style = Avatars.held?(actor) ? Avatars::PHOTO : Avatars::FALLBACK

      {
        "name" => actor.display_name,
        "details" => actor.display_details,
        "note" => (I18n.t("application.person.unconfirmed") if actor.email_unconfirmed?),
        "role" => (I18n.t("application.person.manager") if actor.manages?),
        "avatar" => Avatars.url(actor, style, subject: actor.uuid, size: 128)
      }
    end

    def forget_vanished_actor!
      return if store["actor_id"].blank? || actor.present?

      store.replace({})
      remove_instance_variable(:@actor) if defined?(@actor)
    end

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

    def answering
      return states if @prompting.nil?

      states.take(states.index(@prompting) + 1)
    end

    def states_by_key
      @states_by_key ||= STATES.index_by(&:key).transform_values { |cls| cls.new(self) }
    end
end
