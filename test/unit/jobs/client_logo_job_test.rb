module Masks
  module Server
    require "test_helper"

    class ClientLogoJobTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      LOGO = "https://probe.example.com/logo.png".freeze

      setup do
        @client = create_client(logo_uri: LOGO)
        clear_enqueued_jobs
      end

      test "a logo the server refuses is forgotten, recorded, and never fetched again on its own" do
        stub_request(:get, LOGO).to_return(status: 500)

        perform_enqueued_jobs { within { ClientLogoJob.perform_later(@client.id) } }

        assert_no_enqueued_jobs(only: ClientLogoJob)
        assert within { Event.exists?(action: Event::CLIENT_LOGO_REFUSED, client: @client) }
        assert_nil within { @client.reload.logo }
      end

      test "a logo that is not an image is refused the same way" do
        stub_request(:get, LOGO).to_return(status: 200, body: "<html></html>", headers: { "Content-Type" => "text/html" })

        perform_enqueued_jobs { within { ClientLogoJob.perform_later(@client.id) } }

        assert_no_enqueued_jobs(only: ClientLogoJob)
        assert within { Event.exists?(action: Event::CLIENT_LOGO_REFUSED, client: @client) }
      end
    end
  end
end
