# frozen_string_literal: true

module Masks
  module Providers
    class Abstract
      include SettingsAttribute

      attr_reader :provider

      def initialize(provider)
        @provider = provider
      end

      delegate :setting, :settings, :settings=, to: :provider

      def setup?
        raise NotImplementedError
      end

      def omniauth_strategy
        raise NotImplementedError
      end

      def omniauth_args
        raise NotImplementedError
      end

      def omniauth_opts
        {}
      end

      def identifier(auth_hash)
        auth_hash.dig("info", "name") || auth_hash.dig("info", "nickname") ||
          auth_hash.dig("info", "email")
      end

      def avatar(auth_hash)
        auth_hash.dig("info", "image")
      end
    end
  end
end
