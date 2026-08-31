class Authorization
  attr_reader :client_id, :redirect_uri, :response_type, :state, :nonce,
              :code_challenge, :code_challenge_method, :prompt, :audience,
              :requested_scopes, :max_age, :requested_claims

  def self.from_request(request)
    repeated = Rack::Utils.parse_query(request.query_string)
    repeated = repeated.merge(Rack::Utils.parse_query(request.raw_post)) { |_, a, b| Array(a) + Array(b) } if request.post?
    params = request.params

    new(
      client_id: params["client_id"],
      redirect_uri: params["redirect_uri"],
      response_type: params["response_type"],
      scope: params["scope"],
      state: params["state"],
      nonce: params["nonce"],
      code_challenge: params["code_challenge"],
      code_challenge_method: params["code_challenge_method"],
      prompt: params["prompt"],
      max_age: params["max_age"],
      resource: repeated["resource"],
      request: params["request"],
      request_uri: params["request_uri"],
      claims: params["claims"]
    )
  end

  def initialize(client_id:, redirect_uri:, response_type:, scope: nil, state: nil,
                 nonce: nil, code_challenge: nil, code_challenge_method: nil,
                 prompt: nil, max_age: nil, resource: nil, request: nil,
                 request_uri: nil, claims: nil)
    @requested_claims = self.class.parse_claims(claims)
    @request_object = request.presence
    @request_uri = request_uri.presence
    @client_id = client_id.to_s
    @redirect_uri = redirect_uri.to_s
    @response_type = response_type.to_s
    @requested_scopes = Scopes.list(scope)
    @state = state
    @nonce = nonce
    @code_challenge = code_challenge.presence
    @code_challenge_method = (code_challenge_method.presence || ("S256" if @code_challenge))
    @prompt = Scopes.list(prompt)
    @max_age = max_age.presence&.to_i
    @audience = Array(resource).map(&:to_s).reject(&:empty?).uniq
  end

  def client
    @client ||= Client.authenticating(client_id)
  end

  def granted_scopes
    @granted_scopes ||= client ? client.permitted_scopes(requested_scopes) : []
  end

  def scopes_for(actor)
    return granted_scopes if actor.nil?

    actor.permitted_scopes(granted_scopes)
  end

  def openid?
    granted_scopes.include?(Scopes::OPENID)
  end

  def offline?
    granted_scopes.include?(Scopes::OFFLINE)
  end

  def self.parse_claims(value)
    return value if value.is_a?(Hash)
    return nil if value.blank?

    parsed = JSON.parse(value.to_s)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def request_object?
    @request_object.present?
  end

  def request_uri?
    @request_uri.present?
  end

  def reauthenticate?
    prompt.include?("login")
  end

  def consent?
    prompt.include?("consent")
  end

  def silent?
    prompt.include?("none")
  end

  def validate!
    AuthorizationPolicy.new(self).call
    self
  end

  def issue_code!(actor:, authenticated_at: nil)
    AuthorizationCode.mint!(
      actor: actor,
      authenticated_at: authenticated_at,
      client: client,
      scopes: Scopes.join(scopes_for(actor)),
      audience: audience,
      redirect_uri: redirect_uri,
      requested_claims: requested_claims,
      nonce: nonce,
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method
    )
  end

  def redirect_with(issuer:, **params)
    uri = URI.parse(redirect_uri)
    query = Rack::Utils.parse_query(uri.query)
    query.merge!(params.transform_keys(&:to_s).compact)
    query["state"] = state if state.present?
    query["iss"] = issuer.url
    uri.query = Rack::Utils.build_query(query)
    uri.to_s
  end

  def to_session
    {
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "response_type" => response_type,
      "scope" => Scopes.join(requested_scopes),
      "state" => state,
      "nonce" => nonce,
      "code_challenge" => code_challenge,
      "code_challenge_method" => code_challenge_method,
      "max_age" => max_age,
      "resource" => audience,
      "claims" => requested_claims&.to_json
    }.compact
  end

  def to_params
    to_session.merge("prompt" => prompt.join(" ")).reject { |_, value| value.blank? }
  end

  def self.from_session(data)
    return nil if data.blank?

    new(
      client_id: data["client_id"],
      redirect_uri: data["redirect_uri"],
      response_type: data["response_type"],
      scope: data["scope"],
      state: data["state"],
      nonce: data["nonce"],
      code_challenge: data["code_challenge"],
      code_challenge_method: data["code_challenge_method"],
      max_age: data["max_age"],
      resource: data["resource"],
      claims: data["claims"]
    )
  end
end
