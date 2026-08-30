class Authorization
  attr_reader :client_id, :redirect_uri, :response_type, :state, :nonce,
              :code_challenge, :code_challenge_method, :prompt, :audience,
              :requested_scopes

  def self.from_request(request)
    repeated = Rack::Utils.parse_query(request.query_string)
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
      resource: repeated["resource"]
    )
  end

  def initialize(client_id:, redirect_uri:, response_type:, scope: nil, state: nil,
                 nonce: nil, code_challenge: nil, code_challenge_method: nil,
                 prompt: nil, resource: nil)
    @client_id = client_id.to_s
    @redirect_uri = redirect_uri.to_s
    @response_type = response_type.to_s
    @requested_scopes = Scopes.list(scope)
    @state = state
    @nonce = nonce
    @code_challenge = code_challenge.presence
    @code_challenge_method = (code_challenge_method.presence || ("S256" if @code_challenge))
    @prompt = Scopes.list(prompt)
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

  def issue_code!(actor:)
    AuthorizationCode.mint!(
      actor: actor,
      client: client,
      scopes: Scopes.join(scopes_for(actor)),
      audience: audience,
      redirect_uri: redirect_uri,
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
      "resource" => audience
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
      resource: data["resource"]
    )
  end
end
