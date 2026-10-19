module Masks
  module Server
    require "test_helper"

    class WebfingerTest < ActionDispatch::IntegrationTest
      ISSUER_REL = "http://openid.net/specs/connect/1.0/issuer".freeze

      setup { host! host_for(@tenant) }

      def finger(resource, rel: nil)
        get "/.well-known/webfinger", params: { resource: resource, rel: rel }.compact

        response.status == 200 ? JSON.parse(response.body) : nil
      end

      test "an account on this host is pointed at the issuer, whether or not it exists" do
        create_actor(nickname: "ada")

        %w[ada nobody ada@mail.example].each do |local|
          body = finger("acct:#{local}@#{host_for(@tenant)}", rel: ISSUER_REL)

          assert_response :success, local
          assert_equal "application/jrd+json", response.media_type
          assert_equal "acct:#{local}@#{host_for(@tenant)}", body["subject"]
          assert_equal [ { "rel" => ISSUER_REL, "href" => origin_for(@tenant) } ], body["links"]
        end
      end

      test "the host itself is a resource, and without rel every link is listed" do
        body = finger("https://#{host_for(@tenant)}")

        assert_response :success
        assert_equal ISSUER_REL, body.dig("links", 0, "rel")
        assert_equal origin_for(@tenant), body.dig("links", 0, "href")
        assert_equal "*", response.headers["Access-Control-Allow-Origin"]
      end

      test "a rel this server does not know leaves the links empty" do
        body = finger("acct:ada@#{host_for(@tenant)}", rel: "http://webfinger.net/rel/profile-page")

        assert_response :success
        assert_equal [], body["links"]
      end

      test "another host is not found here" do
        finger("acct:ada@elsewhere.example", rel: ISSUER_REL)
        assert_response :not_found

        finger("https://elsewhere.example/")
        assert_response :not_found
      end

      test "a malformed resource is a bad request" do
        [ "", "ada", "acct:ada", "acct:@#{host_for(@tenant)}", "acct:ada@#{host_for(@tenant)}/x", "ftp://#{host_for(@tenant)}",
          "acct:#{"a" * 600}@#{host_for(@tenant)}" ].each do |resource|
          finger(resource, rel: ISSUER_REL)
          assert_response :bad_request, resource.inspect
        end
      end
    end
  end
end
