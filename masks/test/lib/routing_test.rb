# frozen_string_literal: true
require 'test_helper'

module Masks
  class ServerRoutingTest < Masks::ServerTestCase
  test 'use_masks adds routes' do
    assert_equal '/masks', routes.masks_manage_path
    assert_equal '/login', routes.masks_login_path
    assert_equal '/login/test', routes.masks_login_path(client_id: 'test')
    assert_equal '/login/test/.well-known/openid-configuration', routes.masks_client_discovery_path(client_id: 'test')
    assert_equal '/login/test/jwks', routes.masks_client_jwks_path(client_id: 'test')
    assert_equal '/sso/test', routes.masks_sso_callback_path(provider_id: 'test')
    assert_equal '/auth/token', routes.masks_token_path
    assert_equal '/auth/userinfo', routes.masks_userinfo_path
    assert_equal '/auth/client', routes.masks_client_registration_path
    assert_equal '/auth.graphql', routes.masks_graphql_path
  end

  private

  def routes
    Rails.application.routes.url_helpers
  end
  end
end
