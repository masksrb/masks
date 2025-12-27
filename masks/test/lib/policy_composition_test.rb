# frozen_string_literal: true

require 'test_helper'

module Masks
  class PolicyCompositionTest < Masks::ServerTestCase
    test 'RequestPolicy with device sub-policy' do
      p = Masks::RequestPolicy.new do
        device
      end

      assert_equal 1, p.policies.size
      assert_instance_of Masks::DevicePolicy, p.policies.first
    end

    test 'RequestPolicy with multiple sub-policies' do
      p = Masks::RequestPolicy.new do
        device
        client
        logged_in
      end

      assert_equal 3, p.policies.size
      assert_instance_of Masks::DevicePolicy, p.policies[0]
      assert_instance_of Masks::ClientPolicy, p.policies[1]
      assert_instance_of Masks::LoggedInPolicy, p.policies[2]
    end

    test 'sub-policies with config options' do
      p = Masks::RequestPolicy.new do
        device captcha: :turnstile
        logged_in at: '/dashboard'
        client at: '/api/*', method: :post
      end

      assert_equal :turnstile, p.policies[0].config[:captcha]
      assert_equal '/dashboard', p.policies[1].config[:at]
      assert_equal '/api/*', p.policies[2].config[:at]
      assert_equal :post, p.policies[2].config[:method]
    end

    test 'ControllerPolicy with action matching' do
      p = Masks::ControllerPolicy.new do
        logged_in on: :create
        device on: [:update, :destroy]
      end

      assert_equal :create, p.policies[0].config[:on]
      assert_equal [:update, :destroy], p.policies[1].config[:on]
    end

    test 'ControllerPolicy with mixed matchers' do
      p = Masks::ControllerPolicy.new do
        logged_in at: '/admin/*', on: :index
        device method: :post, on: :create
      end

      assert_equal '/admin/*', p.policies[0].config[:at]
      assert_equal :index, p.policies[0].config[:on]
      assert_equal :post, p.policies[1].config[:method]
      assert_equal :create, p.policies[1].config[:on]
    end

    test 'nested policies with SubPolicies' do
      p = Masks::LoginPolicy.new do
        logged_in
      end

      # LoginPolicy has default_policies that add device and client
      assert p.policies.any? { |pol| pol.is_a?(Masks::DevicePolicy) }
      assert p.policies.any? { |pol| pol.is_a?(Masks::ClientPolicy) }
      assert p.policies.any? { |pol| pol.is_a?(Masks::LoggedInPolicy) }
    end

    test 'policy exclusions' do
      p = Masks::RequestPolicy.new do
        device
      end

      p.exclude('/health', '/metrics')

      assert_includes p.excluded, '/health'
      assert_includes p.excluded, '/metrics'
      # Should also have defaults
      assert_includes p.excluded, '/favicon.ico'
    end

    test 'ControllerPolicy exclusions start empty' do
      p = Masks::ControllerPolicy.new do
        device
      end

      assert_empty p.excluded
      p.exclude('/skip')
      assert_includes p.excluded, '/skip'
    end

    test 'uses inherits policies from named policy' do
      # First configure the request policy with some sub-policies
      Masks.configure do
        policy :request do
          device
          client
        end
      end

      # Create a new policy that uses :request
      p = Masks::RequestPolicy.new do
        uses :request
        logged_in
      end

      # Should have device, client from :request plus logged_in
      assert_equal 3, p.policies.size
      assert_instance_of Masks::DevicePolicy, p.policies[0]
      assert_instance_of Masks::ClientPolicy, p.policies[1]
      assert_instance_of Masks::LoggedInPolicy, p.policies[2]
    end

    test 'policy copy preserves sub-policies' do
      original = Masks::RequestPolicy.new do
        device
        client
      end

      copied = original.copy do
        logged_in
      end

      assert_equal 2, original.policies.size
      assert_equal 3, copied.policies.size
    end

    test 'DSL only active inside block' do
      p = Masks::RequestPolicy.new do
        device
      end

      assert_raises NoMethodError do
        p.device
      end
    end

    test 'request_matches? checks path, method, and block' do
      p = Masks::DevicePolicy.new(at: '/api/*', method: :get)

      request = OpenStruct.new(path: '/api/users', method: 'GET')
      assert p.request_matches?(request)

      request = OpenStruct.new(path: '/api/users', method: 'POST')
      refute p.request_matches?(request)

      request = OpenStruct.new(path: '/other', method: 'GET')
      refute p.request_matches?(request)
    end

    test 'path_matches? with wildcards' do
      p = Masks::DevicePolicy.new(at: '/api/*')

      assert p.path_matches?('/api/users')
      assert p.path_matches?('/api/users/123')
      refute p.path_matches?('/other')
    end

    test 'path_matches? with route params' do
      p = Masks::DevicePolicy.new(at: '/users/:id')

      assert p.path_matches?('/users/123')
      assert p.path_matches?('/users/abc')
      refute p.path_matches?('/users')
      refute p.path_matches?('/other/123')
    end

    test 'path_matches? with multiple patterns' do
      p = Masks::DevicePolicy.new(at: ['/api/*', '/admin/*'])

      assert p.path_matches?('/api/users')
      assert p.path_matches?('/admin/dashboard')
      refute p.path_matches?('/other')
    end

    test 'path_matches? with regex' do
      p = Masks::DevicePolicy.new(at: /^\/v\d+\//)

      assert p.path_matches?('/v1/users')
      assert p.path_matches?('/v2/posts')
      refute p.path_matches?('/api/users')
    end

    test 'method_matches? with single method' do
      p = Masks::DevicePolicy.new(method: :post)

      assert p.method_matches?('POST')
      assert p.method_matches?(:post)
      refute p.method_matches?('GET')
    end

    test 'method_matches? with multiple methods' do
      p = Masks::DevicePolicy.new(method: [:get, :post])

      assert p.method_matches?('GET')
      assert p.method_matches?('POST')
      refute p.method_matches?('DELETE')
    end

    test 'action_matches? defaults to true' do
      p = Masks::DevicePolicy.new

      assert p.action_matches?(:create)
      assert p.action_matches?(:anything)
    end

    test 'ControllerPolicy action_matches? checks config[:on]' do
      p = Masks::ControllerPolicy.new

      # Override action_matches? is on ControllerPolicy
      assert p.action_matches?(:create)

      # Sub-policy with on: config
      sub = Masks::DevicePolicy.new(on: :create)
      # DevicePolicy uses default action_matches? from Policy
      assert sub.action_matches?(:create)
    end

    test 'complex composition with all features' do
      p = Masks::RequestPolicy.new do
        device captcha: :turnstile, after: 5
        client at: '/api/*'
        logged_in at: '/dashboard', method: [:get, :post]
        login at: '/auth/*'
      end

      p.exclude('/health')

      assert_equal 4, p.policies.size
      assert_includes p.excluded, '/health'

      # Check captcha config
      device_policy = p.policies[0]
      assert_equal :turnstile, device_policy.config[:captcha]
      assert_equal 5, device_policy.config[:after]

      # Check path/method configs
      assert_equal '/api/*', p.policies[1].config[:at]
      assert_equal '/dashboard', p.policies[2].config[:at]
      assert_equal [:get, :post], p.policies[2].config[:method]
    end

    test 'MasksPolicy inherits from RequestPolicy' do
      p = Masks::MasksPolicy.new do
        device
      end

      assert_kind_of Masks::RequestPolicy, p
      assert_includes p.excluded, '/favicon.ico'
    end

    test 'policy with default at: * matches everything' do
      p = Masks::DevicePolicy.new

      assert_equal '*', p.config[:at]
      assert p.path_matches?('/anything')
      assert p.path_matches?('/any/nested/path')
    end
  end
end
