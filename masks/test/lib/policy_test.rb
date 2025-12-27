# frozen_string_literal: true
require 'test_helper'

module Masks
  class PolicyTest < Masks::ServerTestCase
    # test 'Masks.policy can build policies with a block' do
      # p = Masks.policy(:test) do
        # device
        # logged_in test: true
        # one_of do
          # this
          # that
        # end
      # end

      # assert_equal 'device', p.policies.first.type
      # assert_equal 'logged_in', p.policies.second.type
      # assert_equal 'one_of', p.policies.third.type
      # assert_equal 'this', p.policies.third.policies.first.type
      # assert_equal 'that', p.policies.third.policies.second.type

      # assert p.policies.second.config[:test]
    # end

    # test 'DSL is disabled outside of a block' do
      # assert_raises NoMethodError do
        # Masks.policy(:test).device
      # end

      # Masks.policy(:test) do
        # device
      # end

      # Masks.policy(:test) do
        # device
      # end

      # assert_equal 'device', Masks.policy(:test).policies.first.type
      # assert_equal 'device', Masks.policy(:test).policies.second.type
    # end

    # test 'Masks.policy inherits from mode policies' do
      # Masks.mode.policies = {
        # 'request' => [{ type: 'device' }, { type: 'logged_in', test: true }]
      # }

      # p = Masks.policy(:request)

      # assert_equal 'device', p.policies.first.type
      # assert_equal 'logged_in', p.policies.second.type
      # assert p.policies.second.config[:test]
    # end

    # test 'Masks.policy returns different "types"' do
      # request = Masks.policy(:request)
      # another = Masks.policy(:another)

      # assert_same request, Masks.policy(:request)
      # assert_same another, Masks.policy(:another)
      # refute_same another, request
    # end

    # test '#match returns a new policy that matches a given request' do
      # base = Masks::InlinePolicy.new
      # base.add do
        # device
        # logged_in on: '/test'
      # end

      # base.exclude('/ignore')

      # request1 = Masks::Shims.rails_request(:get, '/')
      # request2 = Masks::Shims.rails_request(:get, '/test/request')
      # request3 = Masks::Shims.rails_request(:get, '/ignore/test')

      # p1 = base.match(request1)
      # p2 = base.match(request2)
      # p3 = base.match(request3)

      # assert_equal :device, p1.policies.first[:type]
      # assert_nil p1.policies.second

      # assert_equal :device, p2.policies.first[:type]
      # assert_equal :logged_in, p2.policies.second[:type]

      # assert_nil p3
    # end
  end
end
