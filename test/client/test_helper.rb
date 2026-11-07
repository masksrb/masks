$LOAD_PATH.unshift File.expand_path("../../client/lib", __dir__)

require "minitest/autorun"
require_relative "../support/offline"
require "socket"
require "masks/client"
require "masks/client/fake"

FakeIssuer = Masks::Client::Fake

class ClientTest < Minitest::Test
  def setup
    Masks::Client.registry.clear!
    @issuer = FakeIssuer.new(scope: "xixo:catalog:read xixo:catalog:write")
  end

  def teardown
    @issuer.stop
    Masks::Client.registry.clear!
  end

  attr_reader :issuer

  def resource(url: "https://app.test/mcp", scopes: %w[xixo:catalog:read xixo:catalog:write resources:command])
    Masks::Client::Resource.new(issuer: issuer.url, url: url, scopes: scopes)
  end
end
