$LOAD_PATH.unshift File.expand_path("../../client/lib", __dir__)

require "json"
require "socket"
require "masks/client"

class LiveApp
  def initialize(port)
    @port = port
    @logouts = Queue.new
    @server = TCPServer.new("127.0.0.1", port)
    @thread = Thread.new { serve }
  end

  def run
    puts JSON.generate("ready" => true)
    $stdout.flush

    while (line = $stdin.gets)
      asked = JSON.parse(line)
      step = asked["step"]

      break if step == "quit"

      answer = begin
        public_send(step.tr(":", "_"), asked)
      rescue StandardError => error
        { "error" => "#{error.class}: #{error.message}" }
      end

      puts JSON.generate(answer)
      $stdout.flush
    end
  end

  def handshake(asked)
    @handshake = Masks::Client::Handshake.new(
      asked["issuer"], name: asked["name"], resource: asked["resource"], redirect_uris: [ asked["redirect_uri"] ],
      return_to: asked["return_to"], scope: asked["scope"], backchannel_logout_uri: asked["backchannel_logout_uri"]
    )
    @redirect_uri = asked["redirect_uri"]
    @scope = asked["signin_scope"]
    started = @handshake.start
    @handshake_state = started[:state]

    { "url" => started[:url], "state" => started[:state] }
  end

  def handshake_complete(asked)
    @registration = @handshake.complete(query(asked["url"]), state: @handshake_state)
    @session = @registration.session(redirect_uri: @redirect_uri, scope: @scope)

    { "client_id" => @registration.client_id }
  end

  def signin(asked)
    @started = @session.start(prompt: asked["prompt"], max_age: asked["max_age"])

    { "url" => @started[:url] }
  end

  def signin_complete(asked)
    returned = query(asked["url"])

    raise "the state came back changed" unless returned["state"] == @started[:state]

    @tokens = @session.complete(code: returned.fetch("code"), verifier: @started[:verifier])
    identity = @session.identity(@tokens, nonce: @started[:nonce], max_age: @started[:max_age])

    {
      "sub" => identity["sub"], "sid" => identity["sid"], "auth_time" => identity["auth_time"],
      "amr" => identity["amr"], "refresh_token" => !@tokens.refresh_token.nil?, "id_token" => !@tokens.id_token.nil?
    }
  end

  def refresh(_asked)
    renewed = @session.refresh(@tokens.refresh_token)
    rotated = !renewed.refresh_token.nil? && renewed.refresh_token != @tokens.refresh_token &&
              renewed.access_token != @tokens.access_token
    @tokens = renewed

    { "rotated" => rotated, "sub" => @session.identity(renewed)&.fetch("sub", nil) || @session.userinfo(renewed)["sub"] }
  end

  def logout(asked)
    deadline = Time.now + asked.fetch("timeout", 30)
    received = nil

    received = @logouts.pop(timeout: [ deadline - Time.now, 0.1 ].max) while received.nil? && Time.now < deadline

    raise "no logout token arrived" if received.nil?

    { "sid" => received.sid, "sub" => received.subject }
  end

  def machine(asked)
    scope = asked["scope"]
    enrollment = @session.enroll(scope: scope, name: "live machine")
    key = Masks::Client::Key.generate
    dpop = Masks::Client::Key.generate
    registered = Masks::Client::Registration.create(
      @session.issuer, token: enrollment.initial_access_token, name: "live machine",
      grant_types: [ "client_credentials" ], scope: scope, token_endpoint_auth_method: "private_key_jwt",
      jwks: key, dpop_bound_access_tokens: true
    )
    machine = Masks::Client::Session.new(issuer: @session.issuer.url, client_id: registered.client_id, private_key: key, dpop: dpop)
    tokens = machine.client_credentials(scope: scope, resource: asked["resource"])
    introspected = @session.introspect(tokens.access_token)

    {
      "client_id" => registered.client_id, "bound" => tokens.bound?, "active" => introspected.active?,
      "scope" => tokens.scope, "jkt" => introspected["cnf"]&.fetch("jkt", nil) == dpop.thumbprint
    }
  end

  private

    def query(url)
      URI.decode_www_form(URI.parse(url).query.to_s).to_h
    end

    def serve
      loop do
        socket = @server.accept
        Thread.new { respond(socket) }
      end
    end

    def respond(socket)
      line = socket.gets.to_s
      headers = {}

      while (header = socket.gets) && header.strip != ""
        name, value = header.split(":", 2)
        headers[name.to_s.strip.downcase] = value.to_s.strip
      end

      method, path = line.split(" ")
      body = headers["content-length"].to_i.positive? ? socket.read(headers["content-length"].to_i) : ""
      status = 404

      if method == "POST" && path == "/backchannel"
        form = URI.decode_www_form(body).to_h
        @logouts << @session.logout_token(form["logout_token"])
        status = 200
      end

      socket.print "HTTP/1.1 #{status} #{status == 200 ? 'OK' : 'Not Found'}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    rescue StandardError => error
      warn "ruby live app: #{error.class}: #{error.message}"
      socket.print "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" rescue nil
    ensure
      socket.close rescue nil
    end
end

port = ARGV[ARGV.index("--port") + 1].to_i if ARGV.include?("--port")

LiveApp.new(port || 4411).run
