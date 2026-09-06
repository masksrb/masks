require "test_helper"
require "socket"

class ResourceMetadataTest < ActiveSupport::TestCase
  class FakeResource
    attr_reader :port, :paths

    def initialize(documents)
      @documents = documents
      @paths = []
      @lock = Mutex.new
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { serve }
    end

    def url(path = "/mcp")
      "http://127.0.0.1:#{port}#{path}"
    end

    def stop
      @thread.kill
      @server.close
    rescue IOError
      nil
    end

    private

      def serve
        loop do
          socket = @server.accept
          Thread.new { respond(socket) }
        end
      rescue IOError, Errno::EBADF
        nil
      end

      def respond(socket)
        line = socket.gets.to_s
        while (header = socket.gets) && header.strip != ""
        end

        path = line.split(" ")[1].to_s
        @lock.synchronize { @paths << path }
        found = @documents[path]
        body = found.is_a?(String) ? found : JSON.generate(found || { "error" => "not_found" })

        socket.print [
          "HTTP/1.1 #{found ? '200 OK' : '404 Not Found'}",
          "Content-Type: application/json",
          "Content-Length: #{body.bytesize}",
          "Connection: close",
          "", body
        ].join("\r\n")
      rescue Errno::EPIPE, IOError
        nil
      ensure
        socket.close rescue nil
      end
  end

  def with_resource(documents)
    server = FakeResource.new(documents)
    yield server
  ensure
    server.stop
  end

  test "a scope the resource server describes reads as a sentence" do
    published = {
      "/.well-known/oauth-protected-resource/mcp" => {
        "scopes_supported" => [ "uris:catalog:read" ],
        "scope_descriptions" => { "uris:catalog:read" => "Search and read your catalog" }
      }
    }

    with_resource(published) do |server|
      described = ResourceMetadata.describe(server.url, "openid uris:catalog:read")

      assert_equal [
        [ "openid", "Confirm who you are" ],
        [ "uris:catalog:read", "Search and read your catalog" ]
      ], described
    end
  end

  test "the RFC 9728 path is tried before the bare one" do
    with_resource({ "/.well-known/oauth-protected-resource" => { "scope_descriptions" => {} } }) do |server|
      ResourceMetadata.describe(server.url, "uris:catalog:read")

      assert_equal [
        "/.well-known/oauth-protected-resource/mcp",
        "/.well-known/oauth-protected-resource"
      ], server.paths
    end
  end

  test "a resource that describes nothing leaves the scope named rather than blank" do
    with_resource({}) do |server|
      assert_equal [ [ "uris:catalog:read", "Use the uris:catalog:read scope" ] ],
                   ResourceMetadata.describe(server.url, "uris:catalog:read")
    end
  end

  test "a resource that cannot be reached does not stop the screen rendering" do
    described = ResourceMetadata.describe("https://127.0.0.1:1/mcp", "openid uris:catalog:read")

    assert_equal [
      [ "openid", "Confirm who you are" ],
      [ "uris:catalog:read", "Use the uris:catalog:read scope" ]
    ], described
  end

  test "a description is not a place to put a paragraph" do
    published = {
      "/.well-known/oauth-protected-resource/mcp" => {
        "scope_descriptions" => { "uris:catalog:read" => "x" * 500 }
      }
    }

    with_resource(published) do |server|
      description = ResourceMetadata.describe(server.url, "uris:catalog:read").first.last

      assert_operator description.length, :<=, ResourceMetadata::LONGEST
    end
  end

  test "a document is fetched once and held, because consent renders on every sign-in" do
    published = {
      "/.well-known/oauth-protected-resource/mcp" => {
        "scope_descriptions" => { "uris:catalog:read" => "Search and read your catalog" }
      }
    }

    with_resource(published) do |server|
      2.times { ResourceMetadata.describe(server.url, "uris:catalog:read") }

      assert_equal 1, server.paths.count
    end
  end

  test "several resources are asked, and the first to describe a scope wins" do
    first = { "/.well-known/oauth-protected-resource/mcp" => {
      "scope_descriptions" => { "uris:catalog:read" => "Read your catalog" }
    } }
    second = { "/.well-known/oauth-protected-resource/mcp" => {
      "scope_descriptions" => { "uris:catalog:read" => "Something else", "jobs:run" => "Run a job" }
    } }

    with_resource(first) do |one|
      with_resource(second) do |two|
        described = ResourceMetadata.describe([ one.url, two.url ], "uris:catalog:read jobs:run")

        assert_equal [
          [ "jobs:run", "Run a job" ],
          [ "uris:catalog:read", "Read your catalog" ]
        ], described
      end
    end
  end

  test "a document that is not a document is simply not one" do
    with_resource({ "/.well-known/oauth-protected-resource/mcp" => "<html>nope</html>" }) do |server|
      assert_equal [ [ "uris:catalog:read", "Use the uris:catalog:read scope" ] ],
                   ResourceMetadata.describe(server.url, "uris:catalog:read")
    end
  end

  test "a resource that publishes a language tag is read in that language" do
    published = {
      "/.well-known/oauth-protected-resource/mcp" => {
        "scope_descriptions" => { "uris:catalog:read" => "Search and read your catalog" },
        "scope_descriptions#fr" => { "uris:catalog:read" => "Chercher et lire votre catalogue" }
      }
    }

    with_resource(published) do |server|
      I18n.with_locale(:en) do
        assert_equal [ [ "uris:catalog:read", "Search and read your catalog" ] ],
                     ResourceMetadata.describe(server.url, "uris:catalog:read")
      end
    end
  end

  test "a language masks does not speak falls back to the untagged descriptions" do
    published = {
      "/.well-known/oauth-protected-resource/mcp" => {
        "scope_descriptions" => { "uris:catalog:read" => "Search and read your catalog" },
        "scope_descriptions#fr" => { "uris:catalog:read" => "Chercher et lire votre catalogue" }
      }
    }

    with_resource(published) do |server|
      described = Localized.fields(
        JSON.parse(JSON.generate(published.values.first)), "scope_descriptions", locale: :de
      )

      assert_equal({ "uris:catalog:read" => "Search and read your catalog" }, described)
      assert_equal [ [ "uris:catalog:read", "Search and read your catalog" ] ],
                   ResourceMetadata.describe(server.url, "uris:catalog:read")
    end
  end

  test "a region asks for its language when the region itself is not published" do
    document = {
      "scope_descriptions" => { "jobs:run" => "Run a job" },
      "scope_descriptions#fr" => { "jobs:run" => "Lancer une tâche" }
    }

    assert_equal({ "jobs:run" => "Lancer une tâche" },
                 Localized.fields(document, "scope_descriptions", locale: :"fr-CA"))
  end

  test "a tagged document adds to the untagged one rather than replacing it" do
    document = {
      "scope_descriptions" => { "jobs:run" => "Run a job", "jobs:stop" => "Stop a job" },
      "scope_descriptions#fr" => { "jobs:run" => "Lancer une tâche" }
    }

    assert_equal({ "jobs:run" => "Lancer une tâche", "jobs:stop" => "Stop a job" },
                 Localized.fields(document, "scope_descriptions", locale: :fr))
  end
end
