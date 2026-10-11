module Masks
  module Server
    require "test_helper"
    require "vips"

    class BrandingTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada")
      end

      def png
        ::Vips::Image.black(300, 300).cast(:uchar).pngsave_buffer
      end

      test "a tenant's logo and color reach the sign-in page" do
        within do
          TenantLogo.store!(@tenant, png)
          @tenant.update!(accent_color: "#FFDD00")
        end

        get "/login"

        assert_match %(class="auth-mark auth-mark-logo"), response.body
        assert_match "--signal: #ffdd00", response.body
        assert_match "--signal-ink: #000000", response.body, "a light color gets dark text"

        get "/logo", params: { v: @tenant.reload.logo_digest, size: 64 }

        assert_response :ok
        assert_equal Pictures::CONTENT_TYPE, response.media_type
        assert_match "immutable", response.headers["Cache-Control"]
      end

      test "a dark color gets light text, and no color leaves masks' own" do
        within { @tenant.update!(accent_color: "#112244") }
        get "/login"
        assert_match "--signal-ink: #ffffff", response.body

        within { @tenant.update!(accent_color: "") }
        get "/login"
        assert_no_match "--signal:", response.body
      end

      test "a color that skipped validation never reaches the page" do
        within { @tenant.update_column(:accent_color, "#000</style><script>alert(1)</script>") }

        get "/login"

        assert_no_match "<script>alert", response.body
      end

      test "a color that is not a hex color is refused" do
        assert_raises(ActiveRecord::RecordInvalid) { within { @tenant.update!(accent_color: "red; } body { display: none") } }
      end

      test "a tenant without a logo shows its initial and no logo is served" do
        get "/login"
        assert_match %(<span class="auth-mark" aria-hidden="true">D</span>), response.body

        get "/logo"
        assert_response :not_found
      end
    end
  end
end
