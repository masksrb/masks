require "test_helper"

module Auth
  class InternalTest < AuthTestCase
    shared_tests

    def entry_params
      { path: "/auth/testing.json", redirect_uri: "/foobar" }
    end

    def client
      @client ||=
        Masks::Client.create!(
          key: "testing",
          name: "testing",
          client_type: "internal",
          redirect_uris: "/foobar",
        )
    end
  end
end
