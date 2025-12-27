# frozen_string_literal: true
require 'test_helper'

module Masks
  class ServerModeTest < Masks::ServerTestCase
    test 'masks cannot run without a mode specified' do
      Masks.expects(:yml).returns({})

      assert_raises(Masks::InvalidModeError) do
        Masks.mode
      end
    end

    test 'masks cannot run without a mode implemented' do
      Masks.stubs(:yml).returns({ mode: 'invalid' })

      assert_raises(Masks::InvalidModeError) do
        Masks.mode
      end
    end

    test 'masks runs in engine mode' do
      assert Masks.mode.is_a?(Masks::EngineMode)
      assert Masks.mode.id == 'engine'
    end

    test '.env inherits from the Rails env' do
      assert Masks.env == 'test'
    end

    test '.env will default to MASKS_ENV if set' do
      og_env = ENV['MASKS_ENV']

      ENV['MASKS_ENV'] = 'foo'

      assert Masks.env == 'foo'
    ensure
      ENV['MASKS_ENV'] = og_env
    end

    test '.env will default to production if nothing else is set' do
      Rails.expects(:env).returns(nil)
      assert Masks.env == 'production'
    end

    test ".yml loads from the Rails app's config/masks.yml" do
      assert Masks.yml[:foo] == 'bar' # bespoke keys are available in the YML
    end
  end
end
