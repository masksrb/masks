#!/usr/bin/env ruby

require "cgi"
require "json"
require "net/http"
require "open3"
require "openssl"
require "optparse"
require "securerandom"
require "socket"
require "timeout"
require "uri"

HERE = __dir__
ROOT = File.expand_path("../..", HERE)
PORT = ENV.fetch("MASKS_LIVE_PORT", "5558")
TOKEN = ENV.fetch("MASKS_LIVE_TOKEN", "live-run-setup-token-not-for-real-use")
PASSWORD = "a-long-enough-password-for-the-live-run-owner".freeze
ISSUER = "http://localhost:#{PORT}".freeze
BOOT_BUDGET = 180
HANDSHAKE_WAIT = 5.5
STEP_TIMEOUT = 60

SDKS = {
  "ruby" => { label: "Masks::Client", port: 4411, env: { "BUNDLE_GEMFILE" => File.join(ROOT, "client", "Gemfile") },
              command: [ "bundle", "exec", "ruby", File.join(HERE, "ruby.rb") ] },
  "node" => { label: "@masks/server", port: 4412, command: [ "node", File.join(HERE, "node.mjs") ] },
  "python" => { label: "masks-client", port: 4413,
                command: [ "uv", "run", "--frozen", "--project", File.join(ROOT, "python"), "python", File.join(HERE, "python.py") ] },
  "go" => { label: "Go", port: 4414, command: [ "go", "run", "-C", File.join(HERE, "go"), "." ] }
}.freeze

SCENARIOS = %w[handshake sign-in refresh step-up logout machine].freeze
SIGN_IN_SCOPE = %w[openid profile email offline_access].freeze
BIND = ENV.fetch("MASKS_LIVE_BIND", ENV["CI"] ? "0.0.0.0" : "127.0.0.1")

class Failed < StandardError; end

class Browser
  attr_reader :secret

  def initialize(origin)
    @origin = URI(origin)
    @cookies = {}
    @csrf = ""
    @secret = nil
  end

  def set_up!(token:)
    page = get("/login")
    fail!("the setup screen did not show: /login answered #{page.code}") unless page.code == "200" && page.body.include?("Set up")

    body = event("signup", token: token, nickname: "owner", email: "owner@example.invalid",
                           password: PASSWORD, password_confirmation: PASSWORD)
    fail!("the first account was not created", body) unless body["prompt"] == "protect"

    @secret = body.dig("protection", "otp", "secret").to_s.delete(" ")
    fail!("no authenticator secret was offered", body) if @secret.empty?

    body = event("protect:otp", code: fresh_totp)
    fail!("the authenticator code was not accepted", body) if body["warnings"].to_a.any?

    body = event("protect:done", kept: "1")
    fail!("the second factor was not finished", body) unless body["prompt"] == "setup-configure"

    body = event("setup-configure", called: "Live")
    fail!("setup did not settle", body) unless body["settled"]
  end

  def secret=(value)
    @secret = value
  end

  def sign_in!
    get("/login")
    settle(event("identify", identifier: "owner"))
  end

  def signed_in!
    sign_in! if get("/").code.start_with?("3")
  end

  def sign_out!
    get("/")
    response = request(Net::HTTP::Delete.new("/logout", "X-CSRF-Token" => @csrf, "Accept" => "text/html"))
    fail!("signing out answered #{response.code}") unless %w[200 302 303].include?(response.code)
  end

  def approve_handshake(url)
    page = get(path_of(url))
    fail!("the handshake screen answered #{page.code}: #{page.body[0, 300]}") unless page.code == "200"

    hid = page.body[/name="hid"[^>]*value="([^"]+)"/, 1] || page.body[/value="([^"]+)"[^>]*name="hid"/, 1]
    shown = page.body[/name="shown"[^>]*value="([^"]+)"/, 1] || page.body[/value="([^"]+)"[^>]*name="shown"/, 1]
    fail!("the handshake screen has no form to approve: #{page.body[0, 500]}") if hid.nil? || shown.nil?

    sleep HANDSHAKE_WAIT

    form = Net::HTTP::Post.new("/handshake", "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "text/html")
    form.body = URI.encode_www_form("authenticity_token" => @csrf, "hid" => hid, "shown" => shown, "approve" => "yes")
    response = request(form)
    fail!("approving the handshake answered #{response.code}: #{response.body[0, 300]}") unless response.code.start_with?("3")

    response["location"]
  end

  def authorize(url)
    away, page = follow(path_of(url))
    return away if away

    held = page.body[/data-auth="([^"]*)"/, 1]
    fail!("the browser was left on a page without a sign-in: #{page.code} #{page.body[0, 300]}") if held.nil?

    location = settle(JSON.parse(CGI.unescapeHTML(held)))
    fail!("the sign-in settled without sending the browser anywhere") if location.nil?

    away, page = follow(path_of(location))
    fail!("the browser was left on masks with #{page.code}: #{page.body[0, 300]}") if away.nil?

    away
  end

  def totp(at = Time.now.to_i)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    bits = secret.upcase.delete("=").each_char.map { |char| alphabet.index(char).to_s(2).rjust(5, "0") }.join
    key = [ bits[0, bits.size - bits.size % 8] ].pack("B*")
    digest = OpenSSL::HMAC.digest("SHA1", key, [ at / 30 ].pack("Q>"))
    offset = digest.bytes.last & 0x0f

    format("%06d", (digest[offset, 4].unpack1("N") & 0x7fffffff) % 1_000_000)
  end

  def fresh_totp
    step = Time.now.to_i / 30

    if @spent_step && step <= @spent_step
      sleep(((@spent_step + 1) * 30) - Time.now.to_f + 0.2)
      step = Time.now.to_i / 30
    end

    @spent_step = step
    totp(step * 30)
  end

  private

    def settle(body)
      rid = body["rid"]
      retried = 0

      until body["settled"]
        body = case body["prompt"]
        when "identify" then event("identify", rid: rid, identifier: "owner")
        when "first-factor" then event("password", rid: rid, password: PASSWORD)
        when "second-factor" then event("otp", rid: rid, code: fresh_totp)
        when "consent" then event("consent", rid: rid, approve: "1")
        when "signup" then fail!("masks has no account yet, so this stack is fresh: run without --attached", body)
        else fail!("the live run does not know how to answer the #{body['prompt'].inspect} prompt", body)
        end

        if body["warnings"] == [ "invalid-code" ] && (retried += 1) <= 3
          sleep(30 - (Time.now.to_i % 30) + 0.2)
          next
        end

        fail!("masks warned during the sign-in", body) if body["warnings"].to_a.any?
      end

      body["redirectTo"]
    end

    def follow(path, hops = 10)
      response = get(path)

      while response.code.start_with?("3")
        location = URI.join(@origin.to_s, response["location"])
        return [ location.to_s, nil ] unless same_origin?(location)

        fail!("too many redirects") if (hops -= 1).zero?

        response = get(path_of(location.to_s))
      end

      [ nil, response ]
    end

    def same_origin?(uri)
      uri.host == @origin.host && uri.port == @origin.port
    end

    def path_of(url)
      uri = URI.join(@origin.to_s, url)
      fail!("#{url} is not on masks") unless same_origin?(uri)

      "#{uri.path}#{"?#{uri.query}" if uri.query}"
    end

    def fail!(message, body = nil)
      detail = body && (body["warnings"].presence_or_nil || body["prompt"])

      raise Failed, [ message, detail && detail.inspect ].compact.join(": ")
    end

    def get(path)
      request(Net::HTTP::Get.new(path, "Accept" => "text/html"))
    end

    def event(name, rid: nil, **fields)
      path = rid ? "/login?rid=#{URI.encode_www_form_component(rid)}" : "/login"
      request = Net::HTTP::Post.new(path, "Content-Type" => "application/json", "Accept" => "application/json",
                                          "X-CSRF-Token" => @csrf)
      request.body = JSON.generate({ "event" => name }.merge(fields))
      response = request(request)

      JSON.parse(response.body)
    rescue JSON::ParserError
      fail!("masks answered the #{name} event with #{response.code} and no JSON: #{response.body.to_s[0, 200]}")
    end

    def request(request)
      request["Host"] = "#{@origin.host}:#{@origin.port}"
      request["Cookie"] = @cookies.map { |name, value| "#{name}=#{value}" }.join("; ") if @cookies.any?

      response = Net::HTTP.start("127.0.0.1", @origin.port) { |http| http.request(request) }

      response.get_fields("set-cookie").to_a.each do |cookie|
        name, value = cookie.split(";", 2).first.split("=", 2)
        @cookies[name] = value
      end

      if response["content-type"].to_s.include?("html")
        @csrf = response.body[/name="csrf-token" content="([^"]+)"/, 1] || @csrf
      end

      response
    end
end

class Array
  def presence_or_nil
    empty? ? nil : self
  end
end

class App
  attr_reader :key, :port

  def initialize(key, port:, command:, env: {})
    @key = key
    @port = port
    @command = command
    @env = env
  end

  def start
    @stdin, @stdout, @wait = Open3.popen2(@env, *@command, "--port", port.to_s, "--bind", BIND, chdir: ROOT)
    ready = ask_raw
    raise Failed, "#{key} did not report ready: #{ready.inspect}" unless ready["ready"]
  end

  def ask(step, **fields)
    @stdin.puts(JSON.generate({ "step" => step }.merge(fields)))
    @stdin.flush
    answer = ask_raw

    raise Failed, "#{key} failed #{step}: #{answer['error']}" if answer.key?("error")

    answer
  end

  def stop
    ask("quit") rescue nil
    @stdin.close rescue nil
    Timeout.timeout(5) { @wait.value } rescue Process.kill("KILL", @wait.pid) rescue nil
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  private

    def ask_raw
      line = Timeout.timeout(STEP_TIMEOUT) { @stdout.gets }
      raise Failed, "#{key} closed its output" if line.nil?

      JSON.parse(line)
    rescue JSON::ParserError
      raise Failed, "#{key} answered something other than JSON: #{line.inspect}"
    rescue Timeout::Error
      raise Failed, "#{key} did not answer within #{STEP_TIMEOUT} seconds"
    end
end

class Run
  def initialize(browser, app)
    @browser = browser
    @app = app
    @results = {}
    @auth_time = nil
  end

  attr_reader :results

  def perform
    SCENARIOS.each do |scenario|
      break unless attempt(scenario)
    end
  end

  private

    def attempt(scenario)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @finished = nil
      send(scenario.tr("-", "_"))
      @results[scenario] = { ok: true, seconds: (@finished || Process.clock_gettime(Process::CLOCK_MONOTONIC)) - started }
      true
    rescue Failed, Net::HTTPExceptions, SystemCallError, JSON::ParserError, KeyError => error
      @results[scenario] = { ok: false, message: error.message }
      false
    end

    def handshake
      started = @app.ask(
        "handshake", issuer: ISSUER, name: "live-#{@app.key}", resource: @app.url,
        redirect_uri: "#{@app.url}/callback", return_to: "#{@app.url}/handshake",
        backchannel_logout_uri: "#{@app.url}/backchannel",
        scope: SIGN_IN_SCOPE + [ "live-#{@app.key}:" ], signin_scope: SIGN_IN_SCOPE
      )
      returned = @browser.approve_handshake(started.fetch("url"))
      registered = @app.ask("handshake:complete", url: returned)

      raise Failed, "no client_id came back" if registered["client_id"].to_s.empty?
    end

    def sign_in
      completed = signed_in
      @auth_time = completed.fetch("auth_time").to_i

      raise Failed, "the person signed in is #{completed['sub'].inspect}" if completed["sub"].to_s.empty?
      raise Failed, "no refresh token came back" unless completed["refresh_token"]
      raise Failed, "no ID token came back" unless completed["id_token"]
      raise Failed, "no sid in the ID token" if completed["sid"].to_s.empty?
    end

    def refresh
      renewed = @app.ask("refresh")

      raise Failed, "the refresh did not rotate the token" unless renewed["rotated"]
    end

    def step_up
      sleep 1.1
      completed = signed_in(prompt: "login", max_age: 60)

      raise Failed, "auth_time did not move: #{@auth_time} then #{completed['auth_time']}" unless completed.fetch("auth_time").to_i > @auth_time
    end

    def logout
      @browser.sign_out!
      received = @app.ask("logout", timeout: 30)

      raise Failed, "the logout token names no session" if received["sid"].to_s.empty?

      @finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ensure
      @browser.signed_in!
    end

    def machine
      bound = @app.ask("machine", scope: "live-#{@app.key}:agent", resource: @app.url)

      raise Failed, "the machine's token is not bound to its key" unless bound["bound"]
      raise Failed, "the machine's token does not introspect as active" unless bound["active"]
    end

    def signed_in(prompt: nil, max_age: nil)
      started = @app.ask("signin", prompt: prompt, max_age: max_age)
      returned = @browser.authorize(started.fetch("url"))

      @app.ask("signin:complete", url: returned)
    end
end

def stack(*command)
  env = { "MASKS_IMAGE" => $image, "MASKS_LIVE_PORT" => PORT, "MASKS_LIVE_TOKEN" => TOKEN }

  system(env, "docker", "compose", *command, chdir: HERE)
end

def wait_for_masks
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  up = URI("#{ISSUER}/up")

  loop do
    begin
      return if Net::HTTP.get_response(up).is_a?(Net::HTTPSuccess)
    rescue SystemCallError, IOError
      nil
    end

    raise Failed, "masks did not answer /up within #{BOOT_BUDGET} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > BOOT_BUDGET

    sleep 0.5
  end
end

def grid(results, keys)
  head = [ "SDK", *SCENARIOS ]
  rows = keys.map do |key|
    [ SDKS[key][:label] ] + SCENARIOS.map do |scenario|
      held = results[key][scenario]

      if held.nil? then "–"
      elsif held[:ok] then format("✓ %.1fs", held[:seconds])
      else "✗"
      end
    end
  end

  widths = head.each_index.map { |column| ([ head ] + rows).map { |row| row[column].to_s.length }.max }
  line = ->(row) { "| " + row.each_with_index.map { |cell, column| cell.to_s.ljust(widths[column]) }.join(" | ") + " |" }

  [ line.call(head), "| " + widths.map { |width| "-" * width }.join(" | ") + " |", *rows.map(&line) ].join("\n")
end

STATE = File.join(HERE, ".state.json")

options = { only: SDKS.keys, keep: false, attached: false }
OptionParser.new do |parser|
  parser.on("--only LIST", "run only these SDKs, separated by commas") { |list| options[:only] = list.split(",") }
  parser.on("--keep", "leave the stack running afterwards, remembering its owner") { options[:keep] = true }
  parser.on("--attached", "use the stack a --keep run left running") { options[:attached] = true }
end.parse!

$image = ARGV.first || "masks:live"
keys = options[:only] & SDKS.keys
results = Hash.new { |held, key| held[key] = {} }

unless options[:attached]
  unless system("docker", "image", "inspect", $image, out: File::NULL, err: File::NULL)
    system("docker", "pull", $image) || abort("#{$image} is not an image here")
  end

  stack("down", "-v", "--remove-orphans")
  stack("up", "-d", "--quiet-pull") || abort("the live stack did not start")
end

begin
  wait_for_masks

  browser = Browser.new(ISSUER)

  if options[:attached]
    abort("no --keep run left a stack behind: #{STATE} is missing") unless File.exist?(STATE)

    browser.secret = JSON.parse(File.read(STATE)).fetch("secret")
    browser.sign_in!
  else
    browser.set_up!(token: TOKEN)
    File.write(STATE, JSON.generate("secret" => browser.secret)) if options[:keep]
  end

  keys.each do |key|
    app = App.new(key, **SDKS[key].slice(:port, :command, :env))

    begin
      browser.signed_in!
      app.start
      run = Run.new(browser, app)
      run.perform
      results[key] = run.results
    rescue Failed => error
      results[key]["handshake"] ||= { ok: false, message: error.message }
    ensure
      app.stop
    end
  end
rescue Failed => error
  stack("logs", "--no-color", "masks")
  abort("live run failed before any SDK ran: #{error.message}")
ensure
  stack("down", "-v", "--remove-orphans") unless options[:keep] || options[:attached]
end

table = grid(results, keys)
failures = results.flat_map { |key, held| held.select { |_, cell| !cell[:ok] }.map { |scenario, cell| "#{SDKS[key][:label]} #{scenario}: #{cell[:message]}" } }
missing = keys.flat_map { |key| (SCENARIOS - results[key].keys).map { |scenario| "#{SDKS[key][:label]} #{scenario}: not reached" } }

puts "\n#{table}\n\n"
failures.each { |failure| puts "  ✗ #{failure}" }
puts if failures.any?

if ENV["GITHUB_STEP_SUMMARY"]
  File.open(ENV["GITHUB_STEP_SUMMARY"], "a") do |summary|
    summary.puts "## Each SDK against a real masks"
    summary.puts
    summary.puts table
    summary.puts
    failures.each { |failure| summary.puts "- ✗ #{failure}" }
  end
end

exit 1 if failures.any? || missing.any?
