module Masks
  module Adapter
    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      attr_reader :key
      attr_accessor :settings

      setting :name, :string, default: -> { default_name }
    end

    class_methods do
      def type
        name.to_s.split("::").last.underscore.delete_suffix("_adapter")
      end
    end

    attr_accessor :deleted

    def initialize(key, settings)
      @key = key
      @settings = settings&.deep_stringify_keys || {}
    end

    def type
      self.class.type
    end

    def default_name
      key.titleize if key
    end

    def setup?
      self.class.settings.all? { |k, v| setting(k) || v[:optional] }
    end

    def config
      self.class.settings.map { |k, v| [k, setting(k)] }.to_h
    end

    def to_param
      key
    end
  end
end
