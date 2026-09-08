require "webauthn/fake_client"

class FakeAuthenticator
  attr_reader :client, :origin

  def initialize(origin)
    @origin = origin
    @client = WebAuthn::FakeClient.new(origin, encoding: :base64url)
  end

  def enrol(options, user_verified: true)
    client.create(challenge: options["challenge"], user_verified: user_verified)
  end

  def assert(options, user_verified: true)
    client.get(challenge: options["challenge"], user_verified: user_verified)
  end
end
