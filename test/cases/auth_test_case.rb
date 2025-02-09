SHARED =
  Dir
    .glob(Rails.root.join("test/auth/shared/**/*.rb"))
    .map do |file|
      require file

      "Auth::Shared::#{Pathname.new(file).basename.to_s.split(".").first.classify}".constantize
    end
module AuthHelpers
  extend ActiveSupport::Concern

  PREFIX = %i[data entry]

  class_methods do
    def entry_params(**opts)
      @entry_params ||= {}
      @entry_params = include_tests(opts) if opts.keys.any?
      @entry_params
    end

    def shared_tests
      SHARED.each { |cls| include cls }
    end

    def entry_name
      self.name
    end
  end

  included do
    attr_reader :entry_id

    setup { traditional_login! }
  end

  def client
    @client ||= Masks::Client.find_by!(key: client_id) if client_id
  end

  def client_id
    @client&.key
  end

  def traditional_login!
    client.update!(require_approval: false)
    client.update!(allow_profiles: false)
    client.disable_second_factor!
  end

  def entry_json(r = nil)
    json = (r || response).parsed_body
    json.dig("entry") || json.dig("data", "enter", "entry")
  end

  def enter(**opts)
    assert client

    opts = entry_params.merge(opts)

    params =
      opts.slice(
        :redirect_uri,
        :scope,
        :response_type,
        :client_id,
        :code_challenge,
        :code_challenge_method,
        :nonce,
      )

    if client.supports_oauth?
      params[:client_id] ||= client_id unless params[:path]
    end

    path = opts.fetch(:path, nil)
    path ||=
      if client.internal?
        "/login/#{client.key}.json"
      else
        params[:client_id] ||= client_id

        "/login.json"
      end

    get "#{path}?#{params.to_query}"

    @entry_id = response.headers["X-Masks-Entry-Id"]

    assert_includes response.content_type, "json"

    response
  end

  def event(name = "", **vars)
    assert @entry_id
    params = vars.delete(:params) || {}
    query =
      "
      mutation($input: EnterInput!) {
        enter(input: $input) {
          entry {
            ...EntryFragment
          }
        }
      }

      #{Masks::MasksSchema.entry_gql}
    "

    post "/login.graphql",
         as: :json,
         params:
           params.merge(
             query:,
             variables: {
               input: {
                 id: @entry_id,
                 event: name,
                 **vars,
               },
             },
           )

    response
  end

  def log_in(identifier, password = "password", authorize: false, **args)
    identify(identifier, **args)
    enter_password(password)
    event_authorize if authorize
  end

  def log_in_via_link(actor, **updates)
    identify(actor.identifier)
    event "login-link:start"
    assert link = actor.login_email.login_links.for_login.active.first
    event "login-link:verify", updates: { code: link.code, **updates }
  end

  def identify(id, **params)
    enter(**params)
    refute_error
    event_identify(id)
    refute_error
  end

  def event_identify(identifier)
    event("identify", updates: { identifier: })
  end

  def enter_password(password)
    event("password:verify", updates: { password: })
  end

  def event_authorize(r = nil)
    event("authorize")
  end

  def assert_prompt(prompt, r = nil)
    assert_equal prompt, entry_json(r).dig(:prompt)
  end

  def refute_prompt(prompt, r = nil)
    assert entry_json(r).dig(:prompt)
    assert_not_equal prompt, entry_json(r).dig(:prompt)
  end

  def assert_artifacts(devices: 0, tokens: 0, jwts: 0, codes: 0)
    assert_equal codes, Masks::AuthorizationCode.count
    assert_equal devices, Masks::Device.count
    assert_equal tokens, Masks::AccessToken.count
    assert_equal jwts, Masks::IdToken.count
  end

  def assert_artifacts(devices: 0, tokens: 0, jwts: 0, codes: 0)
    assert_equal codes, Masks::AuthorizationCode.count
    assert_equal devices, Masks::Device.count
    assert_equal tokens, Masks::AccessToken.count
    assert_equal jwts, Masks::IdToken.count
  end

  def assert_warning(code, r = nil)
    assert_includes entry_json(r).dig(:warnings), code
  end

  def refute_warnings(r = nil)
    assert_empty entry_json(r).dig(:warnings)
  end

  def refute_error(r = nil)
    assert_not entry_json(r).dig(:error)
  end

  def assert_login(r = nil)
    assert_settled(r)
    data = entry_json(r)
    assert data.dig(:redirectUri)
    assert data.dig(:client)
    assert_not data.dig(:error)
    assert_prompt "success", r
  end

  def assert_trusted(r = nil)
    assert entry_json(r).dig(:trusted)
  end

  def refute_trusted(r = nil)
    assert entry_json(r).dig(:trusted)
  end

  def assert_settled(r = nil)
    assert entry_json(r).dig(:settled)
  end

  def refute_settled(r = nil)
    assert_not entry_json(r).dig(:settled)
  end

  def assert_redirect_uri(r = nil)
    redirect_uri = entry_json(r).dig(:redirectUri)
    parsed_uri = URI.parse(redirect_uri)

    {
      uri: parsed_uri,
      url: redirect_uri,
      fragment: Rack::Utils.parse_nested_query(parsed_uri.fragment),
      params: Rack::Utils.parse_nested_query(parsed_uri.query),
    }.deep_stringify_keys
  end

  def assert_token(r = nil, type:, secret:)
    Masks::Token.find_by!(type:, secret:)
  end

  def assert_session(value, keys)
    if value
      assert_equal(value, masks_session.data.dig(*keys))
    else
      assert_not masks_session.data.dig(*keys)
    end
  end

  def masks_session
    request.env["masks.session"]
  end

  def setup_2fa(actor, backup_codes: nil, otp: nil, phone: nil)
    setup_otp(actor) if otp
    setup_phone(actor, phone) if phone

    setup_backup_codes(actor, backup_codes)

    actor.enable_second_factor!
  end

  def setup_phone(actor, number)
    manager.phones.create!(number:)
  end

  def setup_otp(actor)
    actor.otp_secrets.create!
    actor.save
  end

  def setup_backup_codes(actor, codes = nil)
    codes ||= Array.new(10) { SecureRandom.hex(10) }
    actor.save_backup_codes(codes, validate: false)
  end
end

class AuthTestCase < MasksTestCase
  include AuthHelpers
end
